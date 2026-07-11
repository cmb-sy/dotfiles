#!/bin/bash
# Shared helpers for claude/hooks/*_test.sh. Source from each test script.
# Usage: source "${SCRIPT_DIR}/test-helpers.sh", call assert_*, end with print_summary.

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

print_summary() {
  echo ""
  echo "${PASS} passed, ${FAIL} failed"
  [[ "$FAIL" -eq 0 ]]
}
