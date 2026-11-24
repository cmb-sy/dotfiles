#!/usr/bin/env bats
# done のエージェントを順に開いて確認済みにし、元のペインへ戻す。herdr のスタブで呼び出しを検査する。

load "helpers/common"
bats_require_minimum_version 1.5.0

setup() {
  make_tmpdir
  cat > "$TEST_TMPDIR/herdr" <<EOF
#!/bin/bash
if [ "\$1 \$2" = "agent list" ]; then printf '%s' "\${FAKE_LIST:-}"; exit "\${FAKE_LIST_EXIT:-0}"; fi
printf "%s\\n" "\$*" >> "$TEST_TMPDIR/calls"
EOF
  chmod +x "$TEST_TMPDIR/herdr"
  export HERDR_BIN="$TEST_TMPDIR/herdr"
  export HERDR_CLEAR_DELAY=0
  CMD="$BATS_TEST_DIRNAME/../bin/herdr-clear-done"
}

teardown() { rm -rf "$TEST_TMPDIR"; }

agent() { printf '{"pane_id":"%s","agent_status":"%s","focused":%s}' "$1" "$2" "$3"; }

@test "done のペインだけを順に開き、最後に元のペインへ戻る" {
  export FAKE_LIST="{\"result\":{\"agents\":[$(agent a done false),$(agent b working true),$(agent c idle false),$(agent d done false)]}}"
  run "$CMD"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TMPDIR/calls")" = "$(printf 'agent focus a\nagent focus d\nagent focus b')" ]
  [ "$output" = "cleared 2" ]
}

@test "done が無ければフォーカスを動かさない" {
  export FAKE_LIST="{\"result\":{\"agents\":[$(agent a idle true),$(agent b working false)]}}"
  run "$CMD"
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_TMPDIR/calls" ]
  [ "$output" = "cleared 0" ]
}

@test "フォーカス中のペインが無ければ戻らずに終える" {
  export FAKE_LIST="{\"result\":{\"agents\":[$(agent a done false)]}}"
  run "$CMD"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TMPDIR/calls")" = "agent focus a" ]
}

@test "herdr が一覧を返せないときは何もせず 0 で終わる" {
  export FAKE_LIST_EXIT=1
  run "$CMD"
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_TMPDIR/calls" ]
}

@test "壊れた JSON では何もせず 0 で終わる" {
  export FAKE_LIST="not json"
  run "$CMD"
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_TMPDIR/calls" ]
}

@test "引数を渡すと使い方を出して 2 で終わる" {
  run "$CMD" extra
  [ "$status" -eq 2 ]
  echo "$output" | grep -qF "usage: herdr-clear-done"
}
