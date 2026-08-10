#!/usr/bin/env bats
# claude/settings.json のインラインフック配線テスト。
# stdin JSON を渡して post-commit トリガと破壊的コマンドブロックの実挙動を見る。

load "helpers/common"

SETTINGS="${BATS_TEST_DIRNAME}/../claude/settings.json"

# Selected by matcher/content, not index, so reordering settings.json is safe.
post_cmd() {
  jq -r '.hooks.PostToolUse[] | select(.matcher=="Bash") | .hooks[].command
         | select(contains("post-commit"))' "$SETTINGS"
}

block_cmd() {
  jq -r '.hooks.PreToolUse[] | select(.matcher=="Bash") | .hooks[].command
         | select(contains("BLOCK"))' "$SETTINGS"
}

setup() {
  make_tmpdir
  mkdir -p "$TEST_TMPDIR/.claude/hooks"
  printf '#!/bin/bash\necho CALLED\n' > "$TEST_TMPDIR/.claude/hooks/post-commit.sh"
  chmod +x "$TEST_TMPDIR/.claude/hooks/post-commit.sh"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

# Runs the trigger against a stubbed post-commit.sh under a throwaway HOME.
run_post() {  # $1=stdin payload
  printf '%s' "$1" | HOME="$TEST_TMPDIR" bash -c "$(post_cmd)" 2>&1
}

run_block() {  # $1=stdin payload -> echo exit code
  printf '%s' "$1" | bash -c "$(block_cmd)" >/dev/null 2>&1
  echo $?
}

@test "post-commit trigger exists in settings" {
  run post_cmd
  [ -n "$output" ]
}

@test "destructive block exists in settings" {
  run block_cmd
  [ -n "$output" ]
}

@test "git commit triggers post-commit hook" {
  run run_post '{"tool_input":{"command":"git commit -m test"}}'
  printf '%s' "$output" | grep -qF "CALLED"
}

@test "non-commit command does not trigger" {
  run run_post '{"tool_input":{"command":"ls -la"}}'
  [ "$output" = "" ]
}

@test "broken JSON does not trigger" {
  run run_post 'not-json'
  [ "$output" = "" ]
}

@test "blocks rm -rf /" {
  run run_block '{"tool_input":{"command":"rm -rf /"}}'
  [ "$output" = "2" ]
}

@test "blocks rm -rf ~" {
  run run_block '{"tool_input":{"command":"rm -rf ~"}}'
  [ "$output" = "2" ]
}

@test "blocks rm -rf /usr" {
  run run_block '{"tool_input":{"command":"rm -rf /usr"}}'
  [ "$output" = "2" ]
}

@test "blocks rm -rf /etc subtree" {
  run run_block '{"tool_input":{"command":"rm -rf /etc/hosts"}}'
  [ "$output" = "2" ]
}

@test "blocks dd if=" {
  run run_block '{"tool_input":{"command":"dd if=/dev/zero of=/dev/sda"}}'
  [ "$output" = "2" ]
}

@test "allows normal command" {
  run run_block '{"tool_input":{"command":"ls -la /usr"}}'
  [ "$output" = "0" ]
}

@test "allows rm -rf of tmp path" {
  run run_block '{"tool_input":{"command":"rm -rf /tmp/foo"}}'
  [ "$output" = "0" ]
}

@test "allows rm -rf of home subdir" {
  run run_block '{"tool_input":{"command":"rm -rf ~/scratch/foo"}}'
  [ "$output" = "0" ]
}

@test "fail-open on empty stdin" {
  run run_block ''
  [ "$output" = "0" ]
}
