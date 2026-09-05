#!/usr/bin/env bats
# test/setup-links.bats — link rules live in one manifest, exceptions included.

load "helpers/common"

@test "setup.zsh declares its links in a manifest array" {
  code=$(grep -v '^[[:space:]]*#' "$REPO_DIR/setup/setup.zsh")
  printf '%s' "$code" | grep -qF 'LINKS=('
}

@test "the herdr exception lives in the manifest, not in a separate branch" {
  code=$(grep -v '^[[:space:]]*#' "$REPO_DIR/setup/setup.zsh")
  printf '%s' "$code" | grep -qF 'herdr/config.toml'
}

@test "karabiner is linked from setup.zsh, not from install.zsh" {
  code=$(grep -v '^[[:space:]]*#' "$REPO_DIR/setup/setup.zsh")
  printf '%s' "$code" | grep -qF 'karabiner'
  hits=$(grep -v '^[[:space:]]*#' "$REPO_DIR/setup/install.zsh" | grep -cF 'ln -sfn') || hits=0
  [ "$hits" -eq 0 ]
}

@test "the git template directory holds hooks and info, not the gitconfig" {
  [ -d "$REPO_DIR/git/template/hooks" ]
  [ -d "$REPO_DIR/git/template/info" ]
  [ ! -e "$REPO_DIR/git/template/.gitconfig" ]
}

@test "templatedir points at the template subdirectory" {
  grep -qF 'templatedir = ~/dotfiles/git/template' "$REPO_DIR/git/.gitconfig"
}

# The grep above cannot tell whether the split worked: git init has to copy the
# hooks and stop copying a .gitconfig into every new repo's .git/.
@test "git init copies the hooks and no gitconfig" {
  make_tmpdir
  sed "s|~/dotfiles/git/template|$REPO_DIR/git/template|" \
    "$REPO_DIR/git/.gitconfig" > "$TEST_TMPDIR/.gitconfig"
  env HOME="$TEST_TMPDIR" GIT_CONFIG_NOSYSTEM=1 git -C "$TEST_TMPDIR" init -q fresh
  [ -f "$TEST_TMPDIR/fresh/.git/hooks/pre-commit" ]
  [ -f "$TEST_TMPDIR/fresh/.git/info/exclude" ]
  strays=$(ls -a "$TEST_TMPDIR/fresh/.git" | grep -c '^\.gitconfig$') || strays=0
  [ "$strays" -eq 0 ]
  rm -rf "$TEST_TMPDIR"
}

# --- dir-opt: 別リポジトリへ張るリンク ---
#
# 宛先の親が無いまま mkdir -p すると、そこへ clone する予定のディレクトリを
# 空で先に作ってしまい、clone が「空でない」で落ちる。検査は文言ではなく
# 「穴が空かないこと」に当てる。

@test "obsidian へのリンクが manifest にあり dir-opt で張られる" {
  code=$(grep -v '^[[:space:]]*#' "$REPO_DIR/setup/setup.zsh")
  printf '%s' "$code" | grep -qF 'obsidian/02_warehouse/dotfiles-skills|dir-opt'
}

@test "dir-opt は宛先の親が無ければディレクトリを作らずに飛ばす" {
  tmp=$(mktemp -d /private/tmp/dotfiles-test.XXXXXX)
  mkdir -p "$tmp/repo/claude/skills"

  # setup.zsh 本体は他の副作用が大きいので、manifest 処理だけを取り出して回す。
  cat > "$tmp/run.zsh" << 'ZSH'
DOTFILES_DIR="$1"; MISSING="$2"
util::warning() { print -r -- "WARN: $*" }
util::info()    { print -r -- "INFO: $*" }
util::link()    { ln -sfn "$1" "$2" }
link::retire_real_dir() { : }
LINKS=( "claude/skills|${MISSING}/vault/02_warehouse/dotfiles-skills|dir-opt" )
ZSH
  # 本物の link::from_manifest を切り出して連結する（実装のコピーを持たない）
  awk '/^link::from_manifest\(\) \{/,/^\}/' "$REPO_DIR/setup/setup.zsh" >> "$tmp/run.zsh"
  echo 'link::from_manifest' >> "$tmp/run.zsh"

  run zsh "$tmp/run.zsh" "$tmp/repo" "$tmp/nowhere"
  [ "$status" -eq 0 ]
  # ★ 本題: clone 先になるはずの場所が作られていないこと
  [ ! -e "$tmp/nowhere/vault" ]
  n=$(printf '%s' "$output" | grep -c 'dir-opt') || n=0
  [ "$n" -ge 1 ]
  rm -rf "$tmp"
}

@test "dir-opt は宛先の親があればリンクを張る" {
  tmp=$(mktemp -d /private/tmp/dotfiles-test.XXXXXX)
  mkdir -p "$tmp/repo/claude/skills" "$tmp/vault/02_warehouse"
  cat > "$tmp/run.zsh" << 'ZSH'
DOTFILES_DIR="$1"; VAULT="$2"
util::warning() { print -r -- "WARN: $*" }
util::info()    { print -r -- "INFO: $*" }
util::link()    { ln -sfn "$1" "$2" }
link::retire_real_dir() { : }
LINKS=( "claude/skills|${VAULT}/02_warehouse/dotfiles-skills|dir-opt" )
ZSH
  awk '/^link::from_manifest\(\) \{/,/^\}/' "$REPO_DIR/setup/setup.zsh" >> "$tmp/run.zsh"
  echo 'link::from_manifest' >> "$tmp/run.zsh"

  run zsh "$tmp/run.zsh" "$tmp/repo" "$tmp/vault"
  [ "$status" -eq 0 ]
  [ -L "$tmp/vault/02_warehouse/dotfiles-skills" ]
  rm -rf "$tmp"
}
