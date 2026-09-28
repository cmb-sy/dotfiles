#!/usr/bin/env bats
# Claude Code の effort は公式の既定値に任せる。
#
# /effort は選んだ値を settings.json の modelSettings に保存し、この machine の
# 全セッションが symlink で同じファイルを読む。保存された値は以後ずっと
# 公式の既定値より優先されるので、固定先は保存値より強い環境変数に置き、
# 値は auto（モデルごとの既定値）にする。その宣言が消えていないことを検査する。

load "helpers/common"

setup() {
  S="$REPO_DIR/claude/settings.json"
}

@test "effort を環境変数で auto に固定している" {
  jq -r '.env.CLAUDE_CODE_EFFORT_LEVEL // ""' "$S" | grep -qx 'auto'
}

@test ".zshrc が effort を別の値で上書きしていない" {
  n=$(grep -v '^[[:space:]]*#' "$REPO_DIR/.zshrc" | grep -c 'CLAUDE_CODE_EFFORT_LEVEL') || n=0
  [ "$n" -eq 0 ]
}
