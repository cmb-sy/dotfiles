#!/usr/bin/env bats
# フォーカス中のセッションに、一覧から選んだ印を付け外しする。
#
# agents パネルの 1 行は「ワークスペース名 · タブ名」で、セッションはタブに
# あたる。ワークスペース名に付けると同じワークスペースの全セッションに付いて
# しまうため、タブが複数あるならタブ側、1 つだけならワークスペース側に付ける
# （1 タブのときパネルはタブ名を表示しないため）。
#
# herdr も fzf も呼ばない。PATH の先頭にスタブを差し込み、workspace list と
# tab list には固定の JSON を返させ、rename 系は引数を記録させて検査する。
# fzf は FZF_PICK が指す行をそのまま返す。osascript もスタブする（die が
# 通知を出すため）。

load "helpers/common"

setup() {
  make_tmpdir
  STUB="$TEST_TMPDIR/bin"
  mkdir -p "$STUB"
  CALLS="$TEST_TMPDIR/calls"
  : >"$CALLS"
  WS_JSON="$TEST_TMPDIR/ws.json"
  TAB_JSON="$TEST_TMPDIR/tab.json"
  BREAD="$TEST_TMPDIR/breadcrumb"
  FZF_MENU="$TEST_TMPDIR/fzf-menu"
  export CALLS WS_JSON TAB_JSON FZF_MENU
  export HERDR_MARK_BREADCRUMB="$BREAD"
  # 印の集合は実行時に書き換わるので、毎テスト使い捨ての場所に置く。
  export HERDR_MARKS_FILE="$TEST_TMPDIR/marks.tsv"
  # 並べ替えは socket API を使うので、ここでは呼ばれたことだけ記録する。
  export HERDR_SORT_BIN="$TEST_TMPDIR/herdr-sort"
  printf '#!/bin/bash\nprintf "sort\\n" >>"$CALLS"\n' >"$HERDR_SORT_BIN"
  chmod +x "$HERDR_SORT_BIN"
  PATH="$STUB:$PATH"

  cat >"$STUB/herdr" <<'STUB'
#!/bin/bash
case "$1 $2" in
  "workspace list") cat "$WS_JSON" ;;
  "tab list") cat "$TAB_JSON" ;;
  "workspace rename") printf 'ws\t%s\t%s\n' "$3" "$4" >>"$CALLS" ;;
  "tab rename") printf 'tab\t%s\t%s\n' "$3" "$4" >>"$CALLS" ;;
  *) exit 1 ;;
esac
STUB

  # 渡された一覧を記録する。--print-query なので 1 行目は必ず入力文字列で、
  # 2 行目に選択行が来る。FZF_PICK が空で FZF_QUERY だけなら「一致なし」(1)、
  # 両方空なら中断 (130) を模す。
  cat >"$STUB/fzf" <<'STUB'
#!/bin/bash
cat >"$FZF_MENU"
printf '%s\n' "${FZF_QUERY:-}"
if [ -n "${FZF_PICK:-}" ]; then printf '%s\n' "$FZF_PICK"; exit 0; fi
if [ -n "${FZF_QUERY:-}" ]; then exit 1; fi
exit 130
STUB

  printf '#!/bin/bash\nexit 0\n' >"$STUB/osascript"
  chmod +x "$STUB/herdr" "$STUB/fzf" "$STUB/osascript"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

# $1 = workspace label, $2 = tab_count, $3 = focused (true/false)
workspace() {
  printf '{"result":{"workspaces":[{"workspace_id":"w1","label":"%s","tab_count":%s,"focused":%s}]}}' \
    "$1" "$2" "$3" >"$WS_JSON"
}

# $1 = tab label, $2 = focused (true/false)
tab() {
  printf '{"result":{"tabs":[{"tab_id":"w1:t1","label":"%s","focused":%s}]}}' \
    "$1" "$2" >"$TAB_JSON"
}

ws_renamed_to() { printf 'ws\tw1\t%s' "$1"; }
tab_renamed_to() { printf 'tab\tw1:t1\t%s' "$1"; }
# rename だけを数える。並べ替えも同じファイルに記録するため、全行を数えると
# 「rename を呼ばない」の検査が並べ替えの 1 行で必ず落ちる。
call_count() {
  local n
  n=$(grep -c -E '^(ws|tab)	' "$CALLS" 2>/dev/null) || n=0
  printf '%s' "$n"
}

@test "選択肢には印 3 種と「外す」が並ぶ" {
  workspace 'proj' 3 true
  tab 'general' true
  FZF_PICK='🤖 対応中' run bash "$REPO_DIR/bin/herdr-mark"
  [ "$status" -eq 0 ]
  cat "$FZF_MENU" | grep -qF '🤖 対応中'
  cat "$FZF_MENU" | grep -qF '📤 返事待ち'
  cat "$FZF_MENU" | grep -qF '🟢 general'
  cat "$FZF_MENU" | grep -qF '✕ 印を外す'
  n=$(grep -c . "$FZF_MENU") || n=0
  [ "$n" -eq 4 ]
}

@test "選んだ印がタブ名に付く（兄弟セッションは巻き込まない）" {
  workspace 'Databricks-Analysis' 5 true
  tab 'general' true
  FZF_PICK='📤 返事待ち' run bash "$REPO_DIR/bin/herdr-mark"
  [ "$status" -eq 0 ]
  cat "$CALLS" | grep -qF "$(tab_renamed_to '📤general')"
  n=$(grep -c '^ws' "$CALLS") || n=0
  [ "$n" -eq 0 ]
}

@test "タブが 1 つだけならワークスペース名に付く" {
  workspace 'distill-vault' 1 true
  tab 'AI-コーチング' true
  FZF_PICK='🟢 general' run bash "$REPO_DIR/bin/herdr-mark"
  [ "$status" -eq 0 ]
  cat "$CALLS" | grep -qF "$(ws_renamed_to '🟢distill-vault')"
  n=$(grep -c '^tab' "$CALLS") || n=0
  [ "$n" -eq 0 ]
}

@test "別の印を選ぶと前の印を重ねずに置き換わる" {
  workspace 'proj' 3 true
  tab '🤖general' true
  FZF_PICK='📤 返事待ち' run bash "$REPO_DIR/bin/herdr-mark"
  [ "$status" -eq 0 ]
  cat "$CALLS" | grep -qF "$(tab_renamed_to '📤general')"
}

@test "「外す」を選ぶと印が消える" {
  workspace 'proj' 3 true
  tab '🤖general' true
  FZF_PICK='✕ 印を外す' run bash "$REPO_DIR/bin/herdr-mark"
  [ "$status" -eq 0 ]
  cat "$CALLS" | grep -qF "$(tab_renamed_to 'general')"
}

@test "集合から外した旧印も剥がせる" {
  # 🔵 は選択肢に無いが、以前付けた行が残っているため剥がせる必要がある。
  workspace '🔵distill-vault' 1 true
  tab 'AI-コーチング' true
  run bash "$REPO_DIR/bin/herdr-mark" off
  [ "$status" -eq 0 ]
  cat "$CALLS" | grep -qF "$(ws_renamed_to 'distill-vault')"
}

@test "選択を中断したら何も変えない" {
  workspace 'proj' 3 true
  tab 'general' true
  run bash "$REPO_DIR/bin/herdr-mark"
  [ "$status" -eq 0 ]
  [ "$(call_count)" -eq 0 ]
}

@test "印が無い状態で off しても rename を呼ばない" {
  workspace 'proj' 3 true
  tab 'general' true
  run bash "$REPO_DIR/bin/herdr-mark" off
  [ "$status" -eq 0 ]
  [ "$(call_count)" -eq 0 ]
}

@test "ワークスペース側に残った印は、タブに付けるときに掃除する" {
  workspace '🔵Databricks-Analysis' 5 true
  tab 'general' true
  run bash "$REPO_DIR/bin/herdr-mark" set '🤖'
  [ "$status" -eq 0 ]
  cat "$CALLS" | grep -qF "$(tab_renamed_to '🤖general')"
  cat "$CALLS" | grep -qF "$(ws_renamed_to 'Databricks-Analysis')"
}

@test "名前に空白を含んでも欠けずに印が付く" {
  workspace 'proj' 3 true
  tab 'my long tab' true
  run bash "$REPO_DIR/bin/herdr-mark" set '🟢'
  [ "$status" -eq 0 ]
  cat "$CALLS" | grep -qF "$(tab_renamed_to '🟢my long tab')"
}

@test "集合に無い印を set に渡すと理由を示して失敗する" {
  workspace 'proj' 3 true
  tab 'general' true
  run bash "$REPO_DIR/bin/herdr-mark" set '🔵'
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -qF 'unknown marker'
  [ "$(call_count)" -eq 0 ]
}

@test "set に印を渡さなければ理由を示して失敗する" {
  workspace 'proj' 3 true
  tab 'general' true
  run bash "$REPO_DIR/bin/herdr-mark" set
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -qF 'set needs a marker'
  [ "$(call_count)" -eq 0 ]
}

@test "不正な action は理由を示して失敗し rename を呼ばない" {
  workspace 'proj' 1 true
  tab '1' true
  run bash "$REPO_DIR/bin/herdr-mark" bogus
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -qF 'unknown action: bogus'
  [ "$(call_count)" -eq 0 ]
}

@test "フォーカス中のワークスペースが無ければ理由を示して失敗する" {
  workspace 'dotfiles' 1 false
  tab '1' true
  run bash "$REPO_DIR/bin/herdr-mark" off
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -qF 'no focused workspace'
  [ "$(call_count)" -eq 0 ]
}

@test "フォーカス中のタブが無ければ理由を示して失敗する" {
  workspace 'dotfiles' 3 true
  tab '1' false
  run bash "$REPO_DIR/bin/herdr-mark" off
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -qF 'no focused tab'
  [ "$(call_count)" -eq 0 ]
}

@test "タブ数が数値でなければ理由を示して失敗する" {
  printf '{"result":{"workspaces":[{"workspace_id":"w1","label":"x","tab_count":"many","focused":true}]}}' >"$WS_JSON"
  tab '1' true
  run bash "$REPO_DIR/bin/herdr-mark" off
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -qF 'non-numeric tab count'
  [ "$(call_count)" -eq 0 ]
}

@test "印だけのラベルは空名に潰さず失敗する" {
  workspace 'proj' 3 true
  tab '🤖' true
  run bash "$REPO_DIR/bin/herdr-mark" off
  [ "$status" -ne 0 ]
  [ "$(call_count)" -eq 0 ]
}

@test "herdr の応答が壊れていれば失敗する" {
  printf 'not json' >"$WS_JSON"
  tab '1' true
  run bash "$REPO_DIR/bin/herdr-mark" off
  [ "$status" -ne 0 ]
  [ "$(call_count)" -eq 0 ]
}

@test "起動しただけで痕跡を残す（キーが発火したかを後から判別するため）" {
  workspace 'proj' 3 true
  tab 'general' true
  run bash "$REPO_DIR/bin/herdr-mark" off
  [ "$status" -eq 0 ]
  cat "$BREAD" | grep -qF 'invoked action=off'
}

@test "失敗する経路でも痕跡は残る" {
  workspace 'proj' 1 false
  tab 'general' true
  run bash "$REPO_DIR/bin/herdr-mark"
  [ "$status" -ne 0 ]
  cat "$BREAD" | grep -qF 'invoked action=pick'
}

@test "picker が想定外の値を返したら適用せず失敗する" {
  # fzf の一覧を書き換えられた、表示が壊れた、といった場合に、未知の文字列を
  # そのまま名前の先頭へ書き込まないことを確かめる。
  workspace 'proj' 3 true
  tab 'general' true
  FZF_PICK='💀 なりすまし' run bash "$REPO_DIR/bin/herdr-mark"
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -qF 'picker returned an unknown marker'
  [ "$(call_count)" -eq 0 ]
}

@test "印を変えたら並べ替えも走る" {
  workspace 'proj' 3 true
  tab 'general' true
  run bash "$REPO_DIR/bin/herdr-mark" set '🤖'
  [ "$status" -eq 0 ]
  cat "$CALLS" | grep -qxF 'sort'
}

@test "一覧に無い文字を打ち込むと印として追加され、そのまま適用される" {
  workspace 'proj' 3 true
  tab 'general' true
  FZF_QUERY='🔥' run bash -c "'$REPO_DIR/bin/herdr-mark' </dev/null 2>&1"
  [ "$status" -eq 0 ]
  cat "$CALLS" | grep -qF "$(tab_renamed_to '🔥general')"
  cut -f1 "$HERDR_MARKS_FILE" | grep -qxF '🔥'
}

@test "追加した印は次回の選択肢に並ぶ" {
  workspace 'proj' 3 true
  tab 'general' true
  FZF_QUERY='🔥' run bash -c "'$REPO_DIR/bin/herdr-mark' </dev/null 2>&1"
  FZF_PICK='🔥' run bash -c "'$REPO_DIR/bin/herdr-mark' </dev/null 2>&1"
  cat "$FZF_MENU" | grep -qF '🔥'
}

@test "既にある印を打ち込んでも二重登録しない" {
  workspace 'proj' 3 true
  tab 'general' true
  FZF_QUERY='🤖' run bash -c "'$REPO_DIR/bin/herdr-mark' </dev/null 2>&1"
  [ "$status" -ne 0 ]
  n=$(cut -f1 "$HERDR_MARKS_FILE" | grep -cxF '🤖') || n=0
  [ "$n" -eq 1 ]
}

@test "空白を含む文字列は印として受け付けない" {
  workspace 'proj' 3 true
  tab 'general' true
  FZF_QUERY='あ い' run bash -c "'$REPO_DIR/bin/herdr-mark' </dev/null 2>&1"
  [ "$status" -ne 0 ]
  [ "$(call_count)" -eq 0 ]
}

@test "長すぎる文字列は印として受け付けない" {
  workspace 'proj' 3 true
  tab 'general' true
  FZF_QUERY='これはマーカーではなく文章です' run bash -c "'$REPO_DIR/bin/herdr-mark' </dev/null 2>&1"
  [ "$status" -ne 0 ]
  [ "$(call_count)" -eq 0 ]
}

@test "打ち込みも選択もしなければ何も変えない" {
  workspace 'proj' 3 true
  tab 'general' true
  run bash -c "'$REPO_DIR/bin/herdr-mark' </dev/null 2>&1"
  [ "$status" -eq 0 ]
  [ "$(call_count)" -eq 0 ]
}
