#!/bin/bash
# Plain-bash unit tests for handover-lib.sh (no external test framework).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="${SCRIPT_DIR}/../skills/handover/scripts/handover-lib.sh"
source "$LIB"

PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "[PASS] $desc"
    PASS=$((PASS + 1))
  else
    echo "[FAIL] $desc"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_status() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" -eq "$actual" ]]; then
    echo "[PASS] $desc"
    PASS=$((PASS + 1))
  else
    echo "[FAIL] $desc (expected exit $expected, got $actual)"
    FAIL=$((FAIL + 1))
  fi
}

make_tmp_state() {
  local dir
  dir="$(mktemp -d)"
  cat > "${dir}/project-state.json" <<'JSON'
{
  "version": 5,
  "session_id": "test-session",
  "status": "READY",
  "active_tasks": [
    {"id": "T1", "description": "task one", "status": "done", "commit_sha": "abc1234", "file_paths": ["a.sh"], "last_touched": "2026-07-01T00:00:00Z"},
    {"id": "T2", "description": "task two", "status": "in_progress", "file_paths": ["b.sh"], "next_action": "fix b.sh", "last_touched": "2026-07-01T00:00:00Z"}
  ],
  "recent_decisions": [],
  "architecture_changes": [],
  "known_issues": []
}
JSON
  echo "$dir"
}

test_handover_log_prefixes_message() {
  local output
  output="$(_handover_log "hello" 2>&1 >/dev/null)"
  assert_eq "_handover_log prefixes message with [handover]" "[handover] hello" "$output"
}

test_validate_project_state_valid_file() {
  local dir
  dir="$(make_tmp_state)"
  validate_project_state "${dir}/project-state.json"
  assert_status "validate_project_state accepts valid version-5 file" 0 "$?"
  rm -rf "$dir"
}

test_validate_project_state_missing_file() {
  validate_project_state "/tmp/does-not-exist-$$-project-state.json"
  assert_status "validate_project_state rejects missing file" 1 "$?"
}

test_validate_project_state_invalid_json() {
  local dir
  dir="$(mktemp -d)"
  echo "not json" > "${dir}/project-state.json"
  validate_project_state "${dir}/project-state.json"
  assert_status "validate_project_state rejects invalid JSON" 1 "$?"
  rm -rf "$dir"
}

test_validate_project_state_unsupported_version() {
  local dir
  dir="$(mktemp -d)"
  echo '{"version": 3, "status": "READY", "active_tasks": []}' > "${dir}/project-state.json"
  validate_project_state "${dir}/project-state.json"
  assert_status "validate_project_state rejects version 3" 1 "$?"
  rm -rf "$dir"
}

test_validate_project_state_missing_required_field() {
  local dir
  dir="$(mktemp -d)"
  echo '{"version": 5, "status": "READY"}' > "${dir}/project-state.json"
  validate_project_state "${dir}/project-state.json"
  assert_status "validate_project_state rejects missing active_tasks" 1 "$?"
  rm -rf "$dir"
}

test_scan_sessions_returns_ready_sessions_only() {
  local base
  base="$(mktemp -d)"
  mkdir -p "${base}/main/20260701-090000"
  cat > "${base}/main/20260701-090000/project-state.json" <<'JSON'
{
  "version": 5,
  "status": "READY",
  "active_tasks": [
    {"id": "T1", "status": "done"},
    {"id": "T2", "status": "in_progress", "next_action": "fix bug"}
  ]
}
JSON
  mkdir -p "${base}/main/20260701-100000"
  cat > "${base}/main/20260701-100000/project-state.json" <<'JSON'
{
  "version": 5,
  "status": "ALL_COMPLETE",
  "active_tasks": [
    {"id": "T1", "status": "done"}
  ]
}
JSON

  local result count branch fingerprint done_tasks total_tasks next_action
  result="$(scan_sessions "$base")"
  count="$(echo "$result" | jq 'length')"
  assert_eq "scan_sessions excludes ALL_COMPLETE sessions" "1" "$count"

  branch="$(echo "$result" | jq -r '.[0].branch')"
  fingerprint="$(echo "$result" | jq -r '.[0].fingerprint')"
  done_tasks="$(echo "$result" | jq -r '.[0].done_tasks')"
  total_tasks="$(echo "$result" | jq -r '.[0].total_tasks')"
  next_action="$(echo "$result" | jq -r '.[0].next_action')"
  assert_eq "scan_sessions reports branch" "main" "$branch"
  assert_eq "scan_sessions reports fingerprint" "20260701-090000" "$fingerprint"
  assert_eq "scan_sessions reports done_tasks" "1" "$done_tasks"
  assert_eq "scan_sessions reports total_tasks" "2" "$total_tasks"
  assert_eq "scan_sessions reports next_action" "fix bug" "$next_action"

  rm -rf "$base"
}

test_scan_sessions_empty_base_dir() {
  local base result count
  base="$(mktemp -d)"
  result="$(scan_sessions "$base")"
  count="$(echo "$result" | jq 'length')"
  assert_eq "scan_sessions returns empty array for empty base dir" "0" "$count"
  rm -rf "$base"
}

test_scan_sessions_handles_branch_names_with_slashes() {
  local base result branch fingerprint
  base="$(mktemp -d)"
  mkdir -p "${base}/feature/auth-refactor/20260701-090000"
  echo '{"version":5,"status":"READY","active_tasks":[]}' > "${base}/feature/auth-refactor/20260701-090000/project-state.json"

  result="$(scan_sessions "$base")"
  branch="$(echo "$result" | jq -r '.[0].branch')"
  fingerprint="$(echo "$result" | jq -r '.[0].fingerprint')"
  assert_eq "scan_sessions preserves slash-containing branch names" "feature/auth-refactor" "$branch"
  assert_eq "scan_sessions extracts fingerprint under nested branch path" "20260701-090000" "$fingerprint"

  rm -rf "$base"
}

test_scan_sessions_handles_trailing_slash_in_base_dir() {
  local base result branch
  base="$(mktemp -d)"
  mkdir -p "${base}/main/20260701-090000"
  echo '{"version":5,"status":"READY","active_tasks":[]}' > "${base}/main/20260701-090000/project-state.json"

  result="$(scan_sessions "${base}/")"
  branch="$(echo "$result" | jq -r '.[0].branch')"
  assert_eq "scan_sessions strips a trailing slash from base_dir before deriving branch" "main" "$branch"

  rm -rf "$base"
}

make_tmp_git_repo() {
  local dir
  dir="$(mktemp -d)"
  git -C "$dir" init -q -b main
  git -C "$dir" -c user.email="test@example.com" -c user.name="test" commit -q --allow-empty -m "init"
  echo "$dir"
}

test_find_active_session_dir_picks_most_recent_ready() {
  local repo result
  repo="$(make_tmp_git_repo)"
  mkdir -p "${repo}/.agents/handover/main/20260701-090000"
  echo '{"version":5,"status":"READY","active_tasks":[]}' > "${repo}/.agents/handover/main/20260701-090000/project-state.json"
  mkdir -p "${repo}/.agents/handover/main/20260701-100000"
  echo '{"version":5,"status":"ALL_COMPLETE","active_tasks":[]}' > "${repo}/.agents/handover/main/20260701-100000/project-state.json"

  result="$(find_active_session_dir "$repo")"
  assert_eq "find_active_session_dir skips newer ALL_COMPLETE and picks older READY" "${repo}/.agents/handover/main/20260701-090000" "$result"
  rm -rf "$repo"
}

test_find_active_session_dir_no_handover_dir() {
  local repo
  repo="$(make_tmp_git_repo)"
  find_active_session_dir "$repo"
  assert_status "find_active_session_dir returns 1 when no .agents/handover exists" 1 "$?"
  rm -rf "$repo"
}

test_find_active_session_dir_not_a_git_repo() {
  local dir
  dir="$(mktemp -d)"
  find_active_session_dir "$dir"
  assert_status "find_active_session_dir returns 1 outside a git repo" 1 "$?"
  rm -rf "$dir"
}

## Run tests
test_handover_log_prefixes_message
test_validate_project_state_valid_file
test_validate_project_state_missing_file
test_validate_project_state_invalid_json
test_validate_project_state_unsupported_version
test_validate_project_state_missing_required_field
test_scan_sessions_returns_ready_sessions_only
test_scan_sessions_empty_base_dir
test_scan_sessions_handles_branch_names_with_slashes
test_scan_sessions_handles_trailing_slash_in_base_dir
test_find_active_session_dir_picks_most_recent_ready
test_find_active_session_dir_no_handover_dir
test_find_active_session_dir_not_a_git_repo

echo ""
echo "${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]]
