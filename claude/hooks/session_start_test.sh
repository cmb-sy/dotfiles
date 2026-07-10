#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${SCRIPT_DIR}/session-start.sh"

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

assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "[PASS] $desc"
    PASS=$((PASS + 1))
  else
    echo "[FAIL] $desc"
    echo "  expected to contain: $needle"
    echo "  actual: $haystack"
    FAIL=$((FAIL + 1))
  fi
}

make_tmp_git_repo() {
  local dir
  dir="$(mktemp -d)"
  git -C "$dir" init -q -b main
  git -C "$dir" -c user.email="test@example.com" -c user.name="test" commit -q --allow-empty -m "init"
  echo "$dir"
}

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

echo ""
echo "${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]]
