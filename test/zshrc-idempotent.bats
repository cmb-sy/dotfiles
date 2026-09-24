#!/usr/bin/env bats
# .zshrc を二度読み込んでも壊れないこと。
#
# 更新のあとに `source ~/.zshrc` を打つのは普通の操作だが、Ghostty 連携の
# zle-line-init チェーンはそれで自分自身を呼ぶ状態に陥っていた。zsh はこれを
# 「maximum nested function level reached」と報告し、行編集が止まる。
#
# 対話シェルは起こさない。widgets は非対話 zsh でも登録・参照できるので、
# precmd から呼ばれる _claude_tab_setup を直接二度呼んで同じ状況を作る。

load "helpers/common"

setup() {
  make_tmpdir
  GH="$TEST_TMPDIR/ghostty"
  mkdir -p "$GH/shell-integration/zsh"
  : >"$GH/shell-integration/zsh/ghostty-integration"
}

teardown() { rm -rf "$TEST_TMPDIR"; }

# $1 = setup を呼ぶ回数。最後に widgets と hook 数を出力する。
load_zshrc() {
  run zsh -c "
    export GHOSTTY_RESOURCES_DIR='$GH'
    zle -N zle-line-init 2>/dev/null
    source '$REPO_DIR/.zshrc' >/dev/null 2>&1
    repeat $1 _claude_tab_setup
    print -r -- \"orig=\${widgets[_orig_zle_line_init_ct]}\"
    print -r -- \"preexec=\${#preexec_functions}\"
    print -r -- \"precmd=\${#precmd_functions}\"
  "
}

@test "二度目の初期化でも、保存した元ウィジェットが自分自身にならない" {
  # ここが _claude_tab_line_init になると、wrapper が wrapper を呼んで再帰する。
  load_zshrc 2
  n=$(printf '%s' "$output" | grep -c 'orig=user:_claude_tab_line_init') || n=0
  [ "$n" -eq 0 ]
}

@test "一度目の初期化では元のウィジェットが保存される" {
  # 上のテストだけだと、保存を丸ごとやめても通ってしまう。
  load_zshrc 1
  printf '%s' "$output" | grep -qF 'orig=user:zle-line-init'
}

@test "初期化を繰り返してもフックが重ならない" {
  load_zshrc 1
  local once_pre once_pcmd
  once_pre=$(printf '%s' "$output" | sed -n 's/^preexec=//p')
  once_pcmd=$(printf '%s' "$output" | sed -n 's/^precmd=//p')
  load_zshrc 3
  printf '%s' "$output" | grep -qxF "preexec=$once_pre"
  printf '%s' "$output" | grep -qxF "precmd=$once_pcmd"
}

@test "再帰エラーの文言が出ない" {
  load_zshrc 2
  n=$(printf '%s' "$output" | grep -c 'maximum nested function level') || n=0
  [ "$n" -eq 0 ]
}
