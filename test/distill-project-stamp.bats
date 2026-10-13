#!/usr/bin/env bats
# distill-project の記録のファイル名（STAMP）の決め方。
# 開いたままのセッションの続きを古い日付のファイルに書き足すと、サイトの日付が
# ずれ、purge がファイル名の日付で後日の作業ごと消す。日をまたいだら新しい
# ファイルにする。手順は SKILL.md から取り出してそのまま動かす。

load "helpers/common"

setup() {
  make_tmpdir
  SK="$REPO_DIR/claude/skills/distill-project/SKILL.md"
  awk '/^# --- STAMP を決める ---$/ { on = 1; next }
       /^# --- STAMP ここまで ---$/ { exit }
       on { print }' "$SK" >"$TEST_TMPDIR/stamp.sh"
  DEST="$TEST_TMPDIR/記録"
  mkdir -p "$DEST"
  SID="session-aaaa-bbbb"
  TODAY=$(date '+%Y-%m-%d')
  YDAY=$(date -v-1d '+%Y-%m-%d')
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

record() { # record <stamp> <session>
  printf -- '---\ndate: %s\nsession: %s\n---\n# r\n' "${1:0:10}" "$2" >"$DEST/$1.md"
}

run_stamp() {
  run bash -c "DEST='$DEST' SID='$SID'; . '$TEST_TMPDIR/stamp.sh'; echo \"STAMP=\$STAMP PREV=\$PREV\""
}

@test "手順を SKILL.md から取り出せる" {
  grep -qF 'STAMP=' "$TEST_TMPDIR/stamp.sh"
  grep -qF 'sort | tail -1' "$TEST_TMPDIR/stamp.sh"
}

@test "同じセッションの記録が無ければ、今日の日付で新しく作る" {
  run_stamp
  [ "$status" -eq 0 ]
  [[ "$output" == "STAMP=$TODAY-"* ]]
  [[ "$output" == *"PREV=" ]]
}

@test "同じセッションの今日の記録があれば、そのファイルを書き直す" {
  record "$TODAY-0900" "$SID"
  run_stamp
  [ "$output" = "STAMP=$TODAY-0900 PREV=" ]
}

@test "同じセッションの記録が前の日のものだけなら、今日の日付で新しく作り、前の記録を返す" {
  record "$YDAY-0900" "$SID"
  run_stamp
  [[ "$output" == "STAMP=$TODAY-"* ]]
  [[ "$output" == *"PREV=$YDAY-0900" ]]
}

@test "同じセッションの記録が複数あれば、一番新しいものを見る" {
  record "2026-01-01-0900" "$SID"
  record "$TODAY-0800" "$SID"
  record "2026-01-02-0900" "$SID"
  run_stamp
  [ "$output" = "STAMP=$TODAY-0800 PREV=" ]
}

@test "別のセッションの記録は見ない" {
  record "$TODAY-0700" "session-other"
  run_stamp
  [[ "$output" != "STAMP=$TODAY-0700 "* ]]
  [[ "$output" == *"PREV=" ]]
}

@test "stamp の形でない md は見ない" {
  record "$TODAY-0900" "$SID"
  printf -- '---\nsession: %s\n---\n# メモ\n' "$SID" >"$DEST/zz-notes.md"
  printf -- '---\nsession: %s\n---\n# 写し\n' "$SID" >"$DEST/$TODAY-0900-copy.md"
  run_stamp
  [ "$output" = "STAMP=$TODAY-0900 PREV=" ]
}

@test "前の記録は [[ ]] ではなく文字で残すと書いてある（purge の参照の保護で古い記録が残り続けないように）" {
  grep -qF '前の記録:' "$SK"
  grep -qF '`[[ ]]` にしない' "$SK"
}
