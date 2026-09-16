#!/usr/bin/env bats
# フォーカス中のセッションに印を付け外しする。
#
# agents パネルの 1 行は「ワークスペース名 · タブ名」で、セッションはタブに
# あたる。ワークスペース名に付けると同じワークスペースの全セッションに付いて
# しまうため、タブが複数あるならタブ側、1 つだけならワークスペース側に付ける
# （1 タブのときパネルはタブ名を表示しないため）。
#
# herdr 本体は呼ばない。PATH の先頭にスタブを差し込み、workspace list と
# tab list には固定の JSON を返させ、rename 系は引数を記録させて検査する。
# osascript もスタブする（die が通知を出すため）。

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
  export CALLS WS_JSON TAB_JSON
  export HERDR_MARK_BREADCRUMB="$BREAD"
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

  printf '#!/bin/bash\nexit 0\n' >"$STUB/osascript"
  chmod +x "$STUB/herdr" "$STUB/osascript"
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
# grep -c は 0 件のとき「0 を出力して終了コード 1」を返す。素直に
# `|| echo 0` と書くと 0 が二重に出て integer expression エラーになる。
call_count() {
  local n
  n=$(grep -c . "$CALLS" 2>/dev/null) || n=0
  printf '%s' "$n"
}

@test "タブが複数あるならタブ名に印が付く（兄弟セッションは巻き込まない）" {
  workspace 'Databricks-Analysis' 5 true
  tab 'general' true
  run bash "$REPO_DIR/bin/herdr-mark"
  [ "$status" -eq 0 ]
  cat "$CALLS" | grep -qF "$(tab_renamed_to '🔵general')"
  n=$(grep -c '^ws' "$CALLS") || n=0
  [ "$n" -eq 0 ]
}

@test "タブが 1 つだけならワークスペース名に印が付く" {
  workspace 'distill-vault' 1 true
  tab 'AI-コーチング' true
  run bash "$REPO_DIR/bin/herdr-mark"
  [ "$status" -eq 0 ]
  cat "$CALLS" | grep -qF "$(ws_renamed_to '🔵distill-vault')"
  n=$(grep -c '^tab' "$CALLS") || n=0
  [ "$n" -eq 0 ]
}

@test "タブに付いた印をトグルすると外れる" {
  workspace 'Databricks-Analysis' 5 true
  tab '🔵general' true
  run bash "$REPO_DIR/bin/herdr-mark"
  [ "$status" -eq 0 ]
  cat "$CALLS" | grep -qF "$(tab_renamed_to 'general')"
}

@test "ワークスペースに付いた印をトグルすると外れる" {
  workspace '🔵distill-vault' 1 true
  tab 'AI-コーチング' true
  run bash "$REPO_DIR/bin/herdr-mark"
  [ "$status" -eq 0 ]
  cat "$CALLS" | grep -qF "$(ws_renamed_to 'distill-vault')"
}

@test "旧版が付けたワークスペースの印は、タブに付け直すときに掃除する" {
  # 旧版はワークスペース名に付けていたので、同じワークスペースの全行に
  # 印が出ていた。タブ側へ移すときに古い印を残すと二重になる。
  workspace '🔵Databricks-Analysis' 5 true
  tab 'general' true
  run bash "$REPO_DIR/bin/herdr-mark" on
  [ "$status" -eq 0 ]
  cat "$CALLS" | grep -qF "$(tab_renamed_to '🔵general')"
  cat "$CALLS" | grep -qF "$(ws_renamed_to 'Databricks-Analysis')"
}

@test "on は既に印が付いていれば rename を呼ばない" {
  workspace 'Databricks-Analysis' 5 true
  tab '🔵general' true
  run bash "$REPO_DIR/bin/herdr-mark" on
  [ "$status" -eq 0 ]
  [ "$(call_count)" -eq 0 ]
}

@test "off は印が無ければ rename を呼ばない" {
  workspace 'Databricks-Analysis' 5 true
  tab 'general' true
  run bash "$REPO_DIR/bin/herdr-mark" off
  [ "$status" -eq 0 ]
  [ "$(call_count)" -eq 0 ]
}

@test "off はタブとワークスペースの両方から印を外す" {
  workspace '🔵Databricks-Analysis' 5 true
  tab '🔵general' true
  run bash "$REPO_DIR/bin/herdr-mark" off
  [ "$status" -eq 0 ]
  cat "$CALLS" | grep -qF "$(tab_renamed_to 'general')"
  cat "$CALLS" | grep -qF "$(ws_renamed_to 'Databricks-Analysis')"
}

@test "名前に空白を含んでも欠けずに印が付く" {
  workspace 'proj' 3 true
  tab 'my long tab' true
  run bash "$REPO_DIR/bin/herdr-mark" on
  [ "$status" -eq 0 ]
  cat "$CALLS" | grep -qF "$(tab_renamed_to '🔵my long tab')"
}

@test "フォーカス中のワークスペースが無ければ理由を示して失敗する" {
  workspace 'dotfiles' 1 false
  tab '1' true
  run bash "$REPO_DIR/bin/herdr-mark"
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -qF 'no focused workspace'
  [ "$(call_count)" -eq 0 ]
}

@test "フォーカス中のタブが無ければ理由を示して失敗する" {
  workspace 'dotfiles' 3 true
  tab '1' false
  run bash "$REPO_DIR/bin/herdr-mark"
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -qF 'no focused tab'
  [ "$(call_count)" -eq 0 ]
}

@test "タブ数が数値でなければ理由を示して失敗する" {
  printf '{"result":{"workspaces":[{"workspace_id":"w1","label":"x","tab_count":"many","focused":true}]}}' >"$WS_JSON"
  tab '1' true
  run bash "$REPO_DIR/bin/herdr-mark"
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -qF 'non-numeric tab count'
  [ "$(call_count)" -eq 0 ]
}

@test "不正な action は理由を示して失敗し rename を呼ばない" {
  workspace 'dotfiles' 1 true
  tab '1' true
  run bash "$REPO_DIR/bin/herdr-mark" bogus
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -qF 'unknown action: bogus'
  [ "$(call_count)" -eq 0 ]
}

@test "印だけのラベルは空名に潰さず失敗する" {
  workspace 'proj' 3 true
  tab '🔵' true
  run bash "$REPO_DIR/bin/herdr-mark" off
  [ "$status" -ne 0 ]
  [ "$(call_count)" -eq 0 ]
}

@test "herdr の応答が壊れていれば失敗する" {
  printf 'not json' >"$WS_JSON"
  tab '1' true
  run bash "$REPO_DIR/bin/herdr-mark"
  [ "$status" -ne 0 ]
  [ "$(call_count)" -eq 0 ]
}

@test "起動しただけで痕跡を残す（キーが発火したかを後から判別するため）" {
  workspace 'proj' 3 true
  tab 'general' true
  run bash "$REPO_DIR/bin/herdr-mark" on
  [ "$status" -eq 0 ]
  cat "$BREAD" | grep -qF 'invoked action=on'
}

@test "失敗する経路でも痕跡は残る" {
  workspace 'proj' 1 false
  tab 'general' true
  run bash "$REPO_DIR/bin/herdr-mark"
  [ "$status" -ne 0 ]
  cat "$BREAD" | grep -qF 'invoked action=toggle'
}
