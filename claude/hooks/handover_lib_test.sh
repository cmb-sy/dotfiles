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

## Run tests
test_handover_log_prefixes_message
test_validate_project_state_valid_file
test_validate_project_state_missing_file
test_validate_project_state_invalid_json
test_validate_project_state_unsupported_version
test_validate_project_state_missing_required_field

echo ""
echo "${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]]
