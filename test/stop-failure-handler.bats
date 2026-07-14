#!/usr/bin/env bats
# claude/hooks/stop-failure-handler.sh のテスト。
# herdr は実行しないため、herdr / jq をシェル関数でモックする。

SCRIPT="${BATS_TEST_DIRNAME}/../claude/hooks/stop-failure-handler.sh"

setup() {
  HERDR_CALLS="$(mktemp -d)/herdr-calls.log"
  export HERDR_CALLS
}

teardown() {
  rm -f "$HERDR_CALLS"
}

# stop-failure-handler.sh hardcodes $HOME/.claude/stop-failure-debug.log, so
# point HOME at a throwaway dir and read the log from there.
run_handler_isolated() {  # $1=stdin payload, $2=HERDR_PANE_ID (optional)
  local fake_home
  fake_home="$(mktemp -d)"
  mkdir -p "$fake_home/.claude"
  herdr() { printf '%s %s %s\n' "$1" "$2" "$3" >> "$HERDR_CALLS"; }
  export -f herdr
  printf '%s' "$1" | HOME="$fake_home" HERDR_PANE_ID="${2:-}" bash "$SCRIPT" >/dev/null 2>&1
  status=$?
  logged="$(cat "$fake_home/.claude/stop-failure-debug.log" 2>/dev/null)"
  rm -rf "$fake_home"
}

@test "server_error with a pane id sends continue + Enter via herdr" {
  run_handler_isolated '{"hook_event_name":"StopFailure","error":"server_error"}' "wA:p9"
  [ "$status" -eq 0 ]
  [ -f "$HERDR_CALLS" ]
  grep -q 'pane send-text wA:p9' "$HERDR_CALLS"
  grep -q 'pane send-keys wA:p9' "$HERDR_CALLS"
}

@test "logs the raw event regardless of error type" {
  run_handler_isolated '{"hook_event_name":"StopFailure","error":"server_error"}' "wA:p9"
  [[ "$logged" == *'"error":"server_error"'* ]]
}

@test "rate_limit does not trigger herdr" {
  run_handler_isolated '{"hook_event_name":"StopFailure","error":"rate_limit"}' "wA:p9"
  [ "$status" -eq 0 ]
  [ ! -s "$HERDR_CALLS" ]
}

@test "overloaded does not trigger herdr" {
  run_handler_isolated '{"hook_event_name":"StopFailure","error":"overloaded"}' "wA:p9"
  [ ! -s "$HERDR_CALLS" ]
}

@test "missing HERDR_PANE_ID skips herdr even for server_error" {
  run_handler_isolated '{"hook_event_name":"StopFailure","error":"server_error"}' ""
  [ "$status" -eq 0 ]
  [ ! -s "$HERDR_CALLS" ]
}

@test "malformed JSON does not crash and does not trigger herdr" {
  run_handler_isolated 'not-json' "wA:p9"
  [ "$status" -eq 0 ]
  [ ! -s "$HERDR_CALLS" ]
}

@test "empty stdin does not crash" {
  run_handler_isolated '' "wA:p9"
  [ "$status" -eq 0 ]
  [ ! -s "$HERDR_CALLS" ]
}
