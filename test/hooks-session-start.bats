#!/usr/bin/env bats
# claude/hooks/session-start.sh のテスト。

load "helpers/common"

SCRIPT="${BATS_TEST_DIRNAME}/../claude/hooks/session-start.sh"

setup() {
  GIT_REPO="$(make_tmp_git_repo)"
}

teardown() {
  rm -rf "$GIT_REPO"
}

run_in_repo() {
  cd "$GIT_REPO" && bash "$SCRIPT"
}

seed_ready_session() {
  mkdir -p "$GIT_REPO/.agents/handover/main/20260701-090000"
  cat > "$GIT_REPO/.agents/handover/main/20260701-090000/project-state.json" <<'JSON'
{
  "version": 5,
  "status": "READY",
  "active_tasks": [
    {"id": "T1", "status": "done"},
    {"id": "T2", "status": "in_progress", "next_action": "fix bug"}
  ]
}
JSON
}

@test "session-start.sh exits 0 with no .agents/handover dir" {
  run run_in_repo
  [ "$status" -eq 0 ]
}

@test "session-start.sh prints nothing with no .agents/handover dir" {
  run run_in_repo
  [ "$output" = "" ]
}

@test "session-start.sh announces handover sessions" {
  seed_ready_session
  run run_in_repo
  printf '%s' "$output" | grep -qF "Handover sessions found"
}

@test "session-start.sh shows branch/fingerprint" {
  seed_ready_session
  run run_in_repo
  printf '%s' "$output" | grep -qF "main/20260701-090000"
}

@test "session-start.sh shows task counts" {
  seed_ready_session
  run run_in_repo
  printf '%s' "$output" | grep -qF "1/2"
}
