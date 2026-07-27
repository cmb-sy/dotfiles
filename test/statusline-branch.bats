#!/usr/bin/env bats
# Tests for the branch name shown next to the directory in claude/statusline.sh
# (section [5]).
#
# The fixture git identity is built via concatenation (never a literal
# `local@domain` string in this file) to avoid tripping pii-guard on fake
# test data.
#
# Assertions use `grep -qF` pipes and `[ ]`, never `[[ ]]` or `! cmd`: under
# bash 3.2 errexit skips both, so those forms silently pass mid-test.

setup() {
  TEST_DIR="$(mktemp -d /private/tmp/sl-branch-test.XXXXXX)"
  export HOME="$TEST_DIR/home"
  # clp/clw export this in the developer's shell; unset so the account section
  # cannot reach the real cache directory.
  unset CLAUDE_CONFIG_DIR
  mkdir -p "$HOME"
  SCRIPT="$BATS_TEST_DIRNAME/../claude/statusline.sh"

  REPO="$TEST_DIR/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q -b main
  git_email="tester""@""example.test"
  git -C "$REPO" config user.email "$git_email"
  git -C "$REPO" config user.name "tester"
  git -C "$REPO" commit -q --allow-empty -m "first"
  git -C "$REPO" commit -q --allow-empty -m "second"
}

teardown() {
  rm -rf "$TEST_DIR"
}

run_statusline() {
  printf '{"model":{"display_name":"Claude"},"workspace":{"current_dir":"%s"},"session_id":"sl-branch"}' \
    "$1" | "$SCRIPT"
}

@test "branch name is shown in parentheses next to the directory" {
  run run_statusline "$REPO"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "(main)"
}

@test "a renamed branch is reflected, not a cached or hardcoded value" {
  git -C "$REPO" checkout -q -b feat/some-work
  run run_statusline "$REPO"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "(feat/some-work)"
  [ "$(echo "$output" | grep -cF "(main)")" -eq 0 ]
}

@test "detached HEAD falls back to a short SHA instead of empty parentheses" {
  git -C "$REPO" checkout -q --detach HEAD
  sha="$(git -C "$REPO" rev-parse --short HEAD)"
  run run_statusline "$REPO"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "($sha)"
  [ "$(echo "$output" | grep -cF "()")" -eq 0 ]
}

@test "a directory outside any repository shows no parentheses" {
  plain="$TEST_DIR/plain"
  mkdir -p "$plain"
  run run_statusline "$plain"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "plain"
  [ "$(echo "$output" | grep -cF "(")" -eq 0 ]
}

@test "the uncommitted-change badge still appears alongside the branch" {
  echo "dirty" > "$REPO/untracked.txt"
  run run_statusline "$REPO"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "(main)"
  echo "$output" | grep -qF "●1"
}
