#!/usr/bin/env bats
# zsh の起動設定（.zshenv / .zshrc / sheldon / setup の .config リンク）の検査。
#
# 対話シェルの全体を起こす検査は、ライブの sheldon 設定やネットワークに
# 左右されるので避け、.zshenv は `zsh -f` で直接 source し、.zshrc は
# 宣言の位置と、切り出した判定関数の挙動に当てる。

load "helpers/common"

# Non-comment lines of a file, numbered, so order checks ignore comments.
code_lines() {
  grep -n '' "$1" | grep -v '^[0-9]*:[[:space:]]*#'
}

# Line number of the first non-comment line containing the fixed string $2.
first_line() {
  code_lines "$1" | grep -F -- "$2" | head -1 | cut -d: -f1
}

@test ".zshenv を読んだ後の path に重複が無い" {
  # Start from a PATH that already holds the prepended dirs, as a nested shell
  # or a login shell after path_helper does, and source .zshenv twice.
  run env -i HOME="$HOME" PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" \
    zsh -f -c "source '$REPO_DIR/.zshenv'; source '$REPO_DIR/.zshenv'; print -l \$path"
  [ "$status" -eq 0 ]
  dups=$(printf '%s\n' "$output" | sort | uniq -d | grep -c .) || dups=0
  [ "$dups" -eq 0 ]
}

@test ".zshenv の重複除去が prepend の優先順位を保つ" {
  run env -i HOME="$HOME" PATH="/opt/homebrew/bin:/usr/bin:/bin" \
    zsh -f -c "source '$REPO_DIR/.zshenv'; print -r -- \$path[1]"
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.local/bin" ]
}

@test ".zshenv が SHELL を相対名で上書きしない" {
  run env -i HOME="$HOME" SHELL=/bin/zsh PATH=/usr/bin:/bin \
    zsh -f -c "source '$REPO_DIR/.zshenv'; print -r -- \$SHELL"
  [ "$status" -eq 0 ]
  [ "$output" = "/bin/zsh" ]
}

# The dump check is a function so it can be called here on a fixture dump.
# Prints "fresh" when compinit may skip the audit, "rebuild" otherwise.
dump_check() {
  run zsh -f -c "
    eval \"\$(sed -n '/^_zshrc_dump_is_fresh() {/,/^}/p' '$REPO_DIR/.zshrc')\"
    (( \$+functions[_zshrc_dump_is_fresh] )) || { print -r -- missing-function; exit 0; }
    if _zshrc_dump_is_fresh '$1'; then print -r -- fresh; else print -r -- rebuild; fi
  "
}

@test "compinit の判定: dump が存在しなければ作り直す側に分岐する" {
  dump_check "$BATS_TEST_TMPDIR/no-such-dump"
  [ "$status" -eq 0 ]
  [ "$output" = "rebuild" ]
}

@test "compinit の判定: 今日作った dump は監査を省く側に分岐する" {
  : >"$BATS_TEST_TMPDIR/dump"
  dump_check "$BATS_TEST_TMPDIR/dump"
  [ "$status" -eq 0 ]
  [ "$output" = "fresh" ]
}

@test "compinit の判定: 2 日前の dump は作り直す側に分岐する" {
  : >"$BATS_TEST_TMPDIR/old-dump"
  touch -t "$(date -v-2d +%Y%m%d%H%M)" "$BATS_TEST_TMPDIR/old-dump"
  dump_check "$BATS_TEST_TMPDIR/old-dump"
  [ "$status" -eq 0 ]
  [ "$output" = "rebuild" ]
}

@test "compinit は sheldon source の後ろで呼ばれる" {
  # zsh-completions only extends fpath; a dump built before it loads drops them.
  sheldon=$(first_line "$REPO_DIR/.zshrc" 'sheldon source')
  compinit=$(first_line "$REPO_DIR/.zshrc" 'compinit -C')
  [ -n "$sheldon" ]
  [ -n "$compinit" ]
  [ "$compinit" -gt "$sheldon" ]
}

@test "list-colors の zstyle は LS_COLORS を設定する .aliases.sh の後ろ" {
  aliases=$(first_line "$REPO_DIR/.zshrc" 'source "${DOTFILES:-${HOME}/dotfiles}/.aliases.sh"')
  zstyle=$(first_line "$REPO_DIR/.zshrc" 'list-colors')
  [ -n "$aliases" ]
  [ -n "$zstyle" ]
  [ "$zstyle" -gt "$aliases" ]
}

@test "history-substring-search の上下キーが sheldon source の後ろで割り当てられる" {
  sheldon=$(first_line "$REPO_DIR/.zshrc" 'sheldon source')
  up=$(first_line "$REPO_DIR/.zshrc" "'^[[A' history-substring-search-up")
  down=$(first_line "$REPO_DIR/.zshrc" "'^[[B' history-substring-search-down")
  [ -n "$up" ]
  [ -n "$down" ]
  [ "$up" -gt "$sheldon" ]
}

@test "plugins.toml に dircolors-solarized が無く、TOML として読める" {
  hits=$(grep -v '^[[:space:]]*#' "$REPO_DIR/.config/sheldon/plugins.toml" | grep -cF 'dircolors-solarized') || hits=0
  [ "$hits" -eq 0 ]
  run python3 -c "import sys, tomllib; d = tomllib.load(open(sys.argv[1], 'rb')); print(','.join(sorted(d['plugins'])))" \
    "$REPO_DIR/.config/sheldon/plugins.toml"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qF 'zsh-history-substring-search'
}

@test "setup は読まれない .aliases.sh / .function.zsh を HOME へリンクしない" {
  decl=$(grep -E '^[[:space:]]*HOME_DOTFILES=\(' "$REPO_DIR/setup/setup.zsh")
  [ -n "$decl" ]
  hits=$(printf '%s\n' "$decl" | grep -cE '\.aliases\.sh|\.function\.zsh') || hits=0
  [ "$hits" -eq 0 ]
}

@test "setup の .config リンクは git 追跡ファイルから決まる" {
  # A glob also links untracked runtime dirs (e.g. an app's machine-ID dir).
  code=$(grep -v '^[[:space:]]*#' "$REPO_DIR/setup/setup.zsh")
  printf '%s' "$code" | grep -qF 'ls-files .config'
  globs=$(printf '%s\n' "$code" | grep -cF '/.config/*') || globs=0
  [ "$globs" -eq 0 ]
}
