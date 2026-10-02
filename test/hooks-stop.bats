#!/usr/bin/env bats
# claude/hooks/stop.sh: a normal stop resets this pane's auto-continue counter
# (the one stop-failure-handler.sh caps at 3), and only this pane's.

load "helpers/common"

SCRIPT="${BATS_TEST_DIRNAME}/../claude/hooks/stop.sh"

setup() {
  FAKE_HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$FAKE_HOME/.claude"
  OWN="$FAKE_HOME/.claude/stop-failure-continue-wA_p9.count"
  OTHER="$FAKE_HOME/.claude/stop-failure-continue-wB_p1.count"
  echo 2 > "$OWN"
  echo 2 > "$OTHER"
}

run_stop() {  # $1 = HERDR_PANE_ID (may be empty)
  run env HOME="$FAKE_HOME" HERDR_PANE_ID="$1" bash "$SCRIPT" <<< '{"transcript_path":"/x/t.jsonl"}'
}

@test "正常終了でこのペインの自動 continue カウンタを消す" {
  run_stop "wA:p9"
  [ "$status" -eq 0 ]
  n=$(ls "$FAKE_HOME/.claude" | grep -c 'wA_p9') || n=0
  [ "$n" -eq 0 ]
}

@test "他のペインのカウンタは消さない" {
  run_stop "wA:p9"
  [ "$status" -eq 0 ]
  [ -f "$OTHER" ]
}

@test "HERDR_PANE_ID が無ければカウンタに触れない" {
  run_stop ""
  [ "$status" -eq 0 ]
  [ -f "$OWN" ]
  [ -f "$OTHER" ]
}
