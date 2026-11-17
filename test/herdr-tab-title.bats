#!/usr/bin/env bats
# herdr のタブ名を今の作業名に変える。herdr のスタブで呼び出しを検査する。

load "helpers/common"
bats_require_minimum_version 1.5.0

setup() {
  make_tmpdir
  printf '#!/bin/bash\nprintf "%%s\\n" "$@" >> "%s/calls"\nexit "${FAKE_EXIT:-0}"\n' "$TEST_TMPDIR" > "$TEST_TMPDIR/herdr"
  chmod +x "$TEST_TMPDIR/herdr"
  export HERDR_BIN="$TEST_TMPDIR/herdr"
  export HERDR_TAB_ID="tab-1"
  CMD="$BATS_TEST_DIRNAME/../bin/herdr-tab-title"
}

teardown() { rm -rf "$TEST_TMPDIR"; }

@test "引数を空白でつないだ名前で今のタブを改名する" {
  run "$CMD" "#42" タブ名
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TMPDIR/calls")" = "$(printf 'tab\nrename\ntab-1\n#42 タブ名')" ]
}

@test "herdr の外では何もせず 0 で終わる" {
  HERDR_TAB_ID="" run "$CMD" 名前
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$TEST_TMPDIR/calls" ]
}

@test "日本語 25 文字は文字単位で 20 文字に切る" {
  run "$CMD" "あいうえおかきくけこさしすせそたちつてとなにぬねの"
  [ "$status" -eq 0 ]
  [ "$(tail -n1 "$TEST_TMPDIR/calls")" = "あいうえおかきくけこさしすせそたちつてと" ]
}

@test "改名に失敗したら stderr に 1 行出して 0 で終わる" {
  FAKE_EXIT=1 run --separate-stderr "$CMD" 名前
  [ "$status" -eq 0 ]
  [ "$stderr" = "herdr-tab-title: rename failed" ]
}

@test "空の名前は 2 で終わり herdr を呼ばない" {
  run "$CMD" "   "
  [ "$status" -eq 2 ]
  [ ! -e "$TEST_TMPDIR/calls" ]
}
