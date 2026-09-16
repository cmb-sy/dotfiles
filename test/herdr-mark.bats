#!/usr/bin/env bats
# フォーカス中のワークスペース名に印を付け外しする。
#
# herdr 本体は呼ばない。PATH の先頭にスタブを差し込み、workspace list には
# 固定の JSON を返させ、workspace rename は引数をファイルに記録させて検査する。
# osascript もスタブする（die が通知を出すため、実行するとテスト中に
# 通知バナーが並ぶ）。

load "helpers/common"

setup() {
  make_tmpdir
  STUB="$TEST_TMPDIR/bin"
  mkdir -p "$STUB"
  CALLS="$TEST_TMPDIR/calls"
  : >"$CALLS"
  WS_JSON="$TEST_TMPDIR/ws.json"
  BREAD="$TEST_TMPDIR/breadcrumb"
  export CALLS WS_JSON
  export HERDR_MARK_BREADCRUMB="$BREAD"
  PATH="$STUB:$PATH"

  cat >"$STUB/herdr" <<'STUB'
#!/bin/bash
case "$1 $2" in
  "workspace list") cat "$WS_JSON" ;;
  "workspace rename") printf '%s\t%s\n' "$3" "$4" >>"$CALLS" ;;
  *) exit 1 ;;
esac
STUB

  printf '#!/bin/bash\nexit 0\n' >"$STUB/osascript"
  chmod +x "$STUB/herdr" "$STUB/osascript"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

# $1 = label, $2 = focused (true/false)
workspaces() {
  printf '{"result":{"workspaces":[{"workspace_id":"w1","label":"%s","focused":%s}]}}' \
    "$1" "$2" >"$WS_JSON"
}

renamed_to() { printf 'w1\t%s' "$1"; }

@test "印が無いワークスペースをトグルすると印が付く" {
  workspaces 'dotfiles' true
  run bash "$REPO_DIR/bin/herdr-mark"
  [ "$status" -eq 0 ]
  cat "$CALLS" | grep -qF "$(renamed_to '🔵dotfiles')"
}

@test "印が付いたワークスペースをトグルすると印が外れる" {
  workspaces '🔵dotfiles' true
  run bash "$REPO_DIR/bin/herdr-mark"
  [ "$status" -eq 0 ]
  cat "$CALLS" | grep -qF "$(renamed_to 'dotfiles')"
}

@test "on は既に印が付いていれば rename を呼ばない" {
  workspaces '🔵dotfiles' true
  run bash "$REPO_DIR/bin/herdr-mark" on
  [ "$status" -eq 0 ]
  n=$(grep -c . "$CALLS") || n=0
  [ "$n" -eq 0 ]
}

@test "off は印が無ければ rename を呼ばない" {
  workspaces 'dotfiles' true
  run bash "$REPO_DIR/bin/herdr-mark" off
  [ "$status" -eq 0 ]
  n=$(grep -c . "$CALLS") || n=0
  [ "$n" -eq 0 ]
}

@test "名前に空白を含んでも欠けずに印が付く" {
  workspaces 'my project' true
  run bash "$REPO_DIR/bin/herdr-mark" on
  [ "$status" -eq 0 ]
  cat "$CALLS" | grep -qF "$(renamed_to '🔵my project')"
}

@test "フォーカス中のワークスペースが無ければ理由を示して失敗する" {
  workspaces 'dotfiles' false
  run bash "$REPO_DIR/bin/herdr-mark"
  [ "$status" -ne 0 ]
  # 後続のガードも同じ空文字を拾って落とすため、終了コードだけでは
  # focused 検査が生きているか判別できない。
  printf '%s' "$output" | grep -qF 'no focused workspace'
  n=$(grep -c . "$CALLS") || n=0
  [ "$n" -eq 0 ]
}

@test "不正な action は理由を示して失敗し rename を呼ばない" {
  workspaces 'dotfiles' true
  run bash "$REPO_DIR/bin/herdr-mark" bogus
  [ "$status" -ne 0 ]
  # 理由まで見る。検査を外しても set -u が別の理由で落とすため、
  # 終了コードだけでは action 検査が生きているか判別できない。
  printf '%s' "$output" | grep -qF 'unknown action: bogus'
  n=$(grep -c . "$CALLS") || n=0
  [ "$n" -eq 0 ]
}

@test "印だけのラベルは空名に潰さず失敗する" {
  workspaces '🔵' true
  run bash "$REPO_DIR/bin/herdr-mark" off
  [ "$status" -ne 0 ]
  n=$(grep -c . "$CALLS") || n=0
  [ "$n" -eq 0 ]
}

@test "herdr の応答が壊れていれば失敗する" {
  printf 'not json' >"$WS_JSON"
  run bash "$REPO_DIR/bin/herdr-mark"
  [ "$status" -ne 0 ]
  n=$(grep -c . "$CALLS") || n=0
  [ "$n" -eq 0 ]
}

@test "起動しただけで痕跡を残す（キーが発火したかを後から判別するため）" {
  workspaces 'dotfiles' true
  run bash "$REPO_DIR/bin/herdr-mark" on
  [ "$status" -eq 0 ]
  cat "$BREAD" | grep -qF 'invoked action=on'
}

@test "失敗する経路でも痕跡は残る" {
  workspaces 'dotfiles' false
  run bash "$REPO_DIR/bin/herdr-mark"
  [ "$status" -ne 0 ]
  cat "$BREAD" | grep -qF 'invoked action=toggle'
}
