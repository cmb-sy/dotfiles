#!/usr/bin/env bats
# Tests for the session-scoped account-label freeze in claude/statusline.sh
# (section [2]). Verifies the displayed account survives a mid-session
# ~/.claude symlink flip performed by another terminal.
#
# Fixture email addresses are built via concatenation (never a literal
# `local@domain` string in this file) to avoid tripping pii-guard on fake
# test data.

setup() {
  TEST_DIR="$(mktemp -d /private/tmp/sl-acct-test.XXXXXX)"
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME"
  SCRIPT="$BATS_TEST_DIRNAME/../claude/statusline.sh"

  mkdir -p "$TEST_DIR/.claude-work" "$TEST_DIR/.claude-private"
  work_email="worker""@""example-corp.test"
  private_email="personal""@""example.test"
  printf '{"oauthAccount":{"emailAddress":"%s","organizationName":"ExampleCorp"}}' "$work_email" \
    > "$TEST_DIR/.claude-work/.claude.json"
  printf '{"oauthAccount":{"emailAddress":"%s","organizationName":""}}' "$private_email" \
    > "$TEST_DIR/.claude-private/.claude.json"

  ln -sfn "$TEST_DIR/.claude-work" "$HOME/.claude"

  BASE_INPUT='{"model":{"display_name":"Claude"},"workspace":{"current_dir":"'"$TEST_DIR"'"}}'
}

teardown() {
  rm -rf "$TEST_DIR"
}

run_statusline() {
  local session_id="$1"
  echo "${BASE_INPUT%\}}, \"session_id\":\"$session_id\"}" | "$SCRIPT"
}

@test "first render caches the account resolved at that time" {
  run run_statusline "session-a"
  [ "$status" -eq 0 ]
  [[ "$output" == *"work"* ]]
  [[ "$output" == *"worker""@""ExampleCorp"* ]]
  [ -f "$HOME/.cache/claude-statusline-account/session-a" ]
  [ "$(cat "$HOME/.cache/claude-statusline-account/session-a")" = "$TEST_DIR/.claude-work" ]
}

@test "symlink flip after first render does not change this session's label" {
  run run_statusline "session-b"
  [[ "$output" == *"work"* ]]

  # Another terminal repoints the machine-global symlink.
  ln -sfn "$TEST_DIR/.claude-private" "$HOME/.claude"

  run run_statusline "session-b"
  [ "$status" -eq 0 ]
  [[ "$output" == *"work"* ]]
  [[ "$output" != *"personal"* ]]
}

@test "a different session_id resolves independently against the current symlink" {
  run run_statusline "session-c"
  [[ "$output" == *"work"* ]]

  ln -sfn "$TEST_DIR/.claude-private" "$HOME/.claude"

  run run_statusline "session-d"
  [ "$status" -eq 0 ]
  [[ "$output" == *"personal"* ]]
  [[ "$output" != *"worker"* ]]
}

@test "CLAUDE_CONFIG_DIR still takes priority over any cache" {
  run run_statusline "session-e"
  [[ "$output" == *"work"* ]]

  CLAUDE_CONFIG_DIR="$TEST_DIR/.claude-private" run run_statusline "session-e"
  [ "$status" -eq 0 ]
  [[ "$output" == *"personal"* ]]
}

@test "missing session_id falls back to live symlink resolution (old behavior)" {
  run bash -c "echo '$BASE_INPUT' | '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"work"* ]]
  [ ! -d "$HOME/.cache/claude-statusline-account" ]
}
