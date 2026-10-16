#!/usr/bin/env bats
# 起動時だけ effort を low にし、セッション中は /effort で切り替えられるようにする。
#
# --effort はその起動プロセスにだけ効く。CLAUDE_CODE_EFFORT_LEVEL は /effort より
# 強いので、settings.json やシェルには置かない。

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

@test "launchers start claude at low effort" {
  for fn in clp clw clpa clwa clpc clwc; do
    args="$(launch_args "$fn")"
    # The stub must have run, or a missing file would pass the check below.
    printf '%s\n' "$args" | head -n 1 | grep -qx 'stub-ran'
    n=$(printf '%s\n' "$args" | awk 'prev == "--effort" && $0 == "low" { c++ } { prev = $0 } END { print c + 0 }')
    [ "$n" -eq 1 ]
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
