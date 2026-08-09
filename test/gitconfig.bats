#!/usr/bin/env bats
# Tests for git/.gitconfig: the machine-local include must actually resolve.

REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

@test "include.path uses tilde form git actually expands" {
  grep -qF 'path = ~/.gitconfig.local' "$REPO_DIR/git/.gitconfig"
  count=$(grep -c 'path = ${HOME}' "$REPO_DIR/git/.gitconfig" || true)
  [ "$count" -eq 0 ]
}

@test "local include actually takes effect" {
  tmp="$(mktemp -d /private/tmp/gitconfig-test.XXXXXX)"
  cp "$REPO_DIR/git/.gitconfig" "$tmp/.gitconfig"
  printf '[test]\n\tmarker = ok\n' > "$tmp/.gitconfig.local"
  run env HOME="$tmp" GIT_CONFIG_NOSYSTEM=1 git config --get test.marker
  [ "$output" = "ok" ]
  rm -rf "$tmp"
}

@test "sourcetree config is gone" {
  count=$(grep -c 'sourcetree' "$REPO_DIR/git/.gitconfig" || true)
  [ "$count" -eq 0 ]
}
