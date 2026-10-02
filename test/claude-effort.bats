#!/usr/bin/env bats
# Claude Code の effort は /effort で手動で決め、決める場所はそこ 1 つにする。
#
# /effort は選んだ値を settings.json の modelSettings に保存し、全アカウントが
# symlink で同じファイルを読むので、1 回選べば全部に効いて次の起動にも残る。
# 環境変数 CLAUDE_CODE_EFFORT_LEVEL はその保存値より強く /effort を無効にし、
# 起動時の --effort は起動のたびに保存値を上書きする。どちらかが入ると
# 「手動で変えたのに効かない／戻る」になるので、無いことを検査する。

load "helpers/common"

setup() {
  S="$REPO_DIR/claude/settings.json"
  make_tmpdir
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

# Launch one of the .aliases.sh launchers with a stub `claude` that records
# its arguments, in a throwaway HOME so account switching touches nothing real.
launch_args() {
  local fn="$1" stub="$TEST_TMPDIR/bin"
  mkdir -p "$stub" "$TEST_TMPDIR/home"
  # The first line marks that the stub ran; arguments follow, one per line.
  printf '#!/bin/sh\n{ echo stub-ran; printf "%%s\\n" "$@"; } > "%s/args"\n' "$TEST_TMPDIR" > "$stub/claude"
  rm -f "$TEST_TMPDIR/args"
  chmod +x "$stub/claude"
  HOME="$TEST_TMPDIR/home" PATH="$stub:$PATH" DOTFILES="$REPO_DIR" \
    CLAUDE_ACCOUNT_PRIVATE_DIR="$TEST_TMPDIR/home/.claude-private" \
    CLAUDE_ACCOUNT_WORK_DIR="$TEST_TMPDIR/home/.claude-work" \
    zsh -fc "source '$REPO_DIR/.aliases.sh'; $fn" >/dev/null 2>&1
  cat "$TEST_TMPDIR/args"
}

@test "settings.json の env で effort を固定していない" {
  n=$(jq -r '.env | keys[]' "$S" | grep -c '^CLAUDE_CODE_EFFORT_LEVEL$') || n=0
  [ "$n" -eq 0 ]
}

@test "settings.json のトップレベルに effortLevel を置いていない" {
  # modelSettings 配下の effortLevel が /effort の保存先。トップレベルは別の固定になる。
  n=$(jq -r 'has("effortLevel")' "$S" | grep -c '^true$') || n=0
  [ "$n" -eq 0 ]
}

@test "シェルの起動ファイルで effort を固定していない" {
  for f in .zshrc .zshenv .aliases.sh; do
    n=$(grep -v '^[[:space:]]*#' "$REPO_DIR/$f" | grep -c 'CLAUDE_CODE_EFFORT_LEVEL') || n=0
    [ "$n" -eq 0 ]
  done
}

@test "launchers start claude without --effort" {
  for fn in clp clw clpa clwa clpc clwc; do
    args="$(launch_args "$fn")"
    # The stub must have run, or a missing file would pass the check below.
    printf '%s\n' "$args" | head -n 1 | grep -qx 'stub-ran'
    n=$(printf '%s\n' "$args" | grep -cE -e '^--effort(=|$)') || n=0
    [ "$n" -eq 0 ]
  done
}

@test "launchers still pass a configured default model" {
  args="$(CLAUDE_WORK_DEFAULT_MODEL=opus launch_args clw)"
  printf '%s\n' "$args" | grep -qx -e '--model'
  printf '%s\n' "$args" | grep -qx 'opus'
  args="$(CLAUDE_PRIVATE_DEFAULT_MODEL=sonnet launch_args clp)"
  printf '%s\n' "$args" | grep -qx -e '--model'
  printf '%s\n' "$args" | grep -qx 'sonnet'
}
