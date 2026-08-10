#!/usr/bin/env bats
# Tests for git/.gitconfig: the machine-local include must actually resolve.

load "helpers/common"

@test "include.path uses tilde form git actually expands" {
  grep -qF 'path = ~/.gitconfig.local' "$REPO_DIR/git/.gitconfig"
  count=$(grep -c 'path = ${HOME}' "$REPO_DIR/git/.gitconfig" || true)
  [ "$count" -eq 0 ]
}

@test "local include actually takes effect" {
  make_tmpdir
  cp "$REPO_DIR/git/.gitconfig" "$TEST_TMPDIR/.gitconfig"
  printf '[test]\n\tmarker = ok\n' > "$TEST_TMPDIR/.gitconfig.local"
  run env HOME="$TEST_TMPDIR" GIT_CONFIG_NOSYSTEM=1 git config --get test.marker
  [ "$output" = "ok" ]
  rm -rf "$TEST_TMPDIR"
}

@test "sourcetree config is gone" {
  count=$(grep -c 'sourcetree' "$REPO_DIR/git/.gitconfig" || true)
  [ "$count" -eq 0 ]
}
