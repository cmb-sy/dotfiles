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
