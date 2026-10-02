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

@test "keybindings.json は VS Code と Cursor の User ディレクトリへ張られる" {
  code=$(grep -v '^[[:space:]]*#' "$REPO_DIR/setup/setup.zsh")
  printf '%s' "$code" | grep -qF '".vscode/keybindings.json|${HOME}/Library/Application Support/Code/User/keybindings.json|file"'
  printf '%s' "$code" | grep -qF '".vscode/keybindings.json|${HOME}/Library/Application Support/Cursor/User/keybindings.json|file"'
}

# The old setups left these as dangling links in $HOME; cleanup and the CI
# check must both name them, and README documents the same list.
@test "legacy 掃除リストに旧セットアップの 4 名が入っている" {
  # `;` -> space so the last name is matched like the others
  line=$(grep -E '^for legacy in ' "$REPO_DIR/setup/setup.zsh" | tr ';' ' ')
  ci=$(grep -E '^[[:space:]]*for bad in ' "$REPO_DIR/.github/workflows/ci.yml" | tr ';' ' ')
  for n in .aliases .zsh .chezmoi .tmux.conf; do
    printf '%s\n' "$line" | grep -qF " $n "
    printf '%s\n' "$ci" | grep -qF " $n "
    grep -F 'no legacy bad symlinks' "$REPO_DIR/README.md" | grep -qF "\`~/$n\`"
  done
}
