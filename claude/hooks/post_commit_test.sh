#!/bin/bash
# post-commit.sh の unit test（フレームワーク不使用の素の bash）
# 実行: bash claude/hooks/post_commit_test.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${SCRIPT_DIR}/post-commit.sh"

source "${SCRIPT_DIR}/test-helpers.sh"

make_tmp_git_repo_with_commit() {
  local dir
  dir="$(mktemp -d)"
  git -C "$dir" init -q -b main
  echo "hello" > "${dir}/a.sh"
  git -C "$dir" -c user.email="test@example.com" -c user.name="test" add a.sh
  git -C "$dir" -c user.email="test@example.com" -c user.name="test" commit -q -m "add a.sh"
  echo "$dir"
}

test_not_a_git_repo_skips() {
  local dir output exit_status
  dir="$(mktemp -d)"
  output="$(cd "$dir" && env -u CLAUDE_PROJECT_DIR bash "$SCRIPT" 2>&1)"
  exit_status="$?"
  assert_eq "post-commit.sh exits 0 outside a git repository" "0" "$exit_status"
  assert_contains "post-commit.sh logs 'not in a git repository'" "$output" "not in a git repository"
  rm -rf "$dir"
}

test_no_active_session_skips() {
  local repo output exit_status
  repo="$(make_tmp_git_repo_with_commit)"
  output="$(cd "$repo" && CLAUDE_PROJECT_DIR="$repo" bash "$SCRIPT" 2>&1)"
  exit_status="$?"
  assert_eq "post-commit.sh exits 0 when no active session" "0" "$exit_status"
  assert_contains "post-commit.sh logs 'no active handover session'" "$output" "no active handover session"
  rm -rf "$repo"
}

test_active_session_updates_state_and_md() {
  local repo session_dir output sha expected_sha
  repo="$(make_tmp_git_repo_with_commit)"
  session_dir="${repo}/.agents/handover/main/20260701-090000"
  mkdir -p "$session_dir"
  cat > "${session_dir}/project-state.json" <<'JSON'
{
  "version": 5,
  "status": "READY",
  "active_tasks": [
    {"id": "T1", "description": "add a.sh", "status": "in_progress", "file_paths": ["a.sh"], "next_action": "review"}
  ],
  "recent_decisions": [],
  "architecture_changes": [],
  "known_issues": []
}
JSON

  output="$(cd "$repo" && CLAUDE_PROJECT_DIR="$repo" bash "$SCRIPT" 2>&1)"
  assert_contains "post-commit.sh logs successful update" "$output" "updated project-state.json and handover.md"

  sha="$(jq -r '.architecture_changes[-1].commit_sha' "${session_dir}/project-state.json")"
  expected_sha="$(git -C "$repo" log -1 --format=%h)"
  assert_eq "post-commit.sh records short commit SHA" "$expected_sha" "$sha"

  [[ -f "${session_dir}/handover.md" ]]
  assert_eq "post-commit.sh generates handover.md" "0" "$?"

  rm -rf "$repo"
}

test_malformed_task_field_skips_gracefully() {
  local repo session_dir output exit_status
  repo="$(make_tmp_git_repo_with_commit)"
  session_dir="${repo}/.agents/handover/main/20260701-090000"
  mkdir -p "$session_dir"
  cat > "${session_dir}/project-state.json" <<'JSON'
{
  "version": 5,
  "status": "READY",
  "active_tasks": [
    {"id": "T1", "description": "add a.sh", "status": "in_progress", "file_paths": "not-an-array"}
  ],
  "recent_decisions": [],
  "architecture_changes": [],
  "known_issues": []
}
JSON

  output="$(cd "$repo" && CLAUDE_PROJECT_DIR="$repo" bash "$SCRIPT" 2>&1)"
  exit_status="$?"
  assert_eq "post-commit.sh exits 0 when a task's file_paths is not an array" "0" "$exit_status"
  assert_contains "post-commit.sh logs 'failed to update project-state.json'" "$output" "failed to update project-state.json"

  rm -rf "$repo"
}

test_not_a_git_repo_skips
test_no_active_session_skips
test_active_session_updates_state_and_md
test_malformed_task_field_skips_gracefully

print_summary
