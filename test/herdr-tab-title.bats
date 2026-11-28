#!/usr/bin/env bats
# herdr のタブ名を今の作業名に変える。herdr のスタブで呼び出しを検査する。

load "helpers/common"
bats_require_minimum_version 1.5.0

setup() {
  make_tmpdir
  cat > "$TEST_TMPDIR/herdr" <<EOF
#!/bin/bash
if [ "\$1 \$2" = "tab list" ]; then printf '%s' "\${FAKE_TABS:-}"; exit 0; fi
printf "%s\\n" "\$@" >> "$TEST_TMPDIR/calls"
exit "\${FAKE_EXIT:-0}"
EOF
  chmod +x "$TEST_TMPDIR/herdr"
  export HERDR_BIN="$TEST_TMPDIR/herdr"
  export HERDR_TAB_ID="tab-1"
  # The user's marker set (herdr-mark); never the real one.
  export HERDR_MARKS_FILE="$TEST_TMPDIR/marks.tsv"
  printf '%s\t%s\n' '📤' '返事待ち' '🤖' '対応中' > "$HERDR_MARKS_FILE"
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

@test "今のタブ名の末尾の状態の印は、新しい名前に引き継ぐ" {
  FAKE_TABS='{"result":{"tabs":[{"tab_id":"tab-0","label":"9 📤"},{"tab_id":"tab-1","label":"2488 🔥"}]}}' \
    run "$CMD" 2488 etlデプロイ
  [ "$status" -eq 0 ]
  [ "$(tail -n1 "$TEST_TMPDIR/calls")" = "2488 etlデプロイ 🔥" ]
}

@test "印の無いタブ名や読めない一覧では、印を足さない" {
  FAKE_TABS='{"result":{"tabs":[{"tab_id":"tab-1","label":"general"}]}}' run "$CMD" 名前
  [ "$(tail -n1 "$TEST_TMPDIR/calls")" = "名前" ]
  FAKE_TABS='not json' run "$CMD" 名前2
  [ "$(tail -n1 "$TEST_TMPDIR/calls")" = "名前2" ]
}

@test "今のタブ名の先頭の印は、新しい名前の先頭に引き継ぐ" {
  FAKE_TABS='{"result":{"tabs":[{"tab_id":"tab-1","label":"📤2488 旧名"}]}}' run "$CMD" 2488 etlデプロイ
  [ "$status" -eq 0 ]
  [ "$(tail -n1 "$TEST_TMPDIR/calls")" = "📤2488 etlデプロイ" ]
}

@test "先頭の印と末尾の状態の印は両方とも引き継ぐ" {
  FAKE_TABS='{"result":{"tabs":[{"tab_id":"tab-1","label":"🤖2488 🔥"}]}}' run "$CMD" 2488 etl
  [ "$(tail -n1 "$TEST_TMPDIR/calls")" = "🤖2488 etl 🔥" ]
}

@test "先頭の記号が印の一覧に無ければ引き継がない" {
  FAKE_TABS='{"result":{"tabs":[{"tab_id":"tab-1","label":"🔵旧名"}]}}' run "$CMD" 名前
  [ "$(tail -n1 "$TEST_TMPDIR/calls")" = "名前" ]
}

@test "新しい名前が同じ印で始まっていれば重ねない" {
  FAKE_TABS='{"result":{"tabs":[{"tab_id":"tab-1","label":"📤旧名"}]}}' run "$CMD" 📤新名
  [ "$(tail -n1 "$TEST_TMPDIR/calls")" = "📤新名" ]
}

@test "印の一覧が無ければ先頭の印は引き継がない" {
  FAKE_TABS='{"result":{"tabs":[{"tab_id":"tab-1","label":"📤旧名"}]}}' \
    HERDR_MARKS_FILE="$TEST_TMPDIR/missing.tsv" run "$CMD" 名前
  [ "$status" -eq 0 ]
  [ "$(tail -n1 "$TEST_TMPDIR/calls")" = "名前" ]
}
