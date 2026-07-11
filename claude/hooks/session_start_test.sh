#!/bin/bash
# Plain-bash unit tests for session-start.sh (no test framework).
# Run: bash claude/hooks/session_start_test.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${SCRIPT_DIR}/session-start.sh"

source "${SCRIPT_DIR}/test-helpers.sh"

test_no_handover_dir_is_silent() {
  local repo output exit_status
  repo="$(make_tmp_git_repo)"
  output="$(cd "$repo" && bash "$SCRIPT")"
  exit_status="$?"
  assert_eq "session-start.sh exits 0 with no .agents/handover dir" "0" "$exit_status"
  assert_eq "session-start.sh prints nothing with no .agents/handover dir" "" "$output"
  rm -rf "$repo"
}

test_ready_session_prints_banner() {
  local repo output
  repo="$(make_tmp_git_repo)"
  mkdir -p "${repo}/.agents/handover/main/20260701-090000"
  cat > "${repo}/.agents/handover/main/20260701-090000/project-state.json" <<'JSON'
{
  "version": 5,
  "status": "READY",
  "active_tasks": [
    {"id": "T1", "status": "done"},
    {"id": "T2", "status": "in_progress", "next_action": "fix bug"}
  ]
}
JSON
  output="$(cd "$repo" && bash "$SCRIPT")"
  assert_contains "session-start.sh announces handover sessions" "$output" "Handover sessions found"
  assert_contains "session-start.sh shows branch/fingerprint" "$output" "main/20260701-090000"
  assert_contains "session-start.sh shows task counts" "$output" "1/2"
  rm -rf "$repo"
}

test_no_handover_dir_is_silent
test_ready_session_prints_banner

print_summary
