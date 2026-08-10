#!/usr/bin/env bats
# claude/hooks/post-commit.sh のテスト。

load "helpers/common"

SCRIPT="${BATS_TEST_DIRNAME}/../claude/hooks/post-commit.sh"

setup() {
  make_tmpdir
  GIT_REPO="$(make_tmp_git_repo)"
  echo "hello" > "$GIT_REPO/a.sh"
  git -C "$GIT_REPO" -c user.email="test@example.com" -c user.name="test" add a.sh
  git -C "$GIT_REPO" -c user.email="test@example.com" -c user.name="test" \
    commit -q -m "add a.sh"
  SESSION_DIR="$GIT_REPO/.agents/handover/main/20260701-090000"
}

teardown() {
  rm -rf "$TEST_TMPDIR" "$GIT_REPO"
}

run_hook() {
  cd "$GIT_REPO" && CLAUDE_PROJECT_DIR="$GIT_REPO" bash "$SCRIPT" 2>&1
}

run_hook_outside_repo() {
  cd "$TEST_TMPDIR" && env -u CLAUDE_PROJECT_DIR bash "$SCRIPT" 2>&1
}

seed_session() {  # $1=value for T1's file_paths
  mkdir -p "$SESSION_DIR"
  cat > "$SESSION_DIR/project-state.json" <<JSON
{
  "version": 5,
  "status": "READY",
  "active_tasks": [
    {"id": "T1", "description": "add a.sh", "status": "in_progress", "file_paths": $1, "next_action": "review"}
  ],
  "recent_decisions": [],
  "architecture_changes": [],
  "known_issues": []
}
JSON
}

@test "post-commit.sh exits 0 outside a git repository" {
  run run_hook_outside_repo
  [ "$status" -eq 0 ]
}

@test "post-commit.sh logs 'not in a git repository'" {
  run run_hook_outside_repo
  printf '%s' "$output" | grep -qF "not in a git repository"
}

@test "post-commit.sh exits 0 when no active session" {
  run run_hook
  [ "$status" -eq 0 ]
}

@test "post-commit.sh logs 'no active handover session'" {
  run run_hook
  printf '%s' "$output" | grep -qF "no active handover session"
}

@test "post-commit.sh logs successful update" {
  seed_session '["a.sh"]'
  run run_hook
  printf '%s' "$output" | grep -qF "updated project-state.json and handover.md"
}

@test "post-commit.sh records short commit SHA" {
  seed_session '["a.sh"]'
  run_hook >/dev/null
  run jq -r '.architecture_changes[-1].commit_sha' "$SESSION_DIR/project-state.json"
  [ "$output" = "$(git -C "$GIT_REPO" log -1 --format=%h)" ]
}

@test "post-commit.sh generates handover.md" {
  seed_session '["a.sh"]'
  run_hook >/dev/null
  [ -f "$SESSION_DIR/handover.md" ]
}

@test "post-commit.sh exits 0 when a task's file_paths is not an array" {
  seed_session '"not-an-array"'
  run run_hook
  [ "$status" -eq 0 ]
}

@test "post-commit.sh logs 'failed to update project-state.json'" {
  seed_session '"not-an-array"'
  run run_hook
  printf '%s' "$output" | grep -qF "failed to update project-state.json"
}
