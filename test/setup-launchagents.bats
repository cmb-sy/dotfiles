#!/usr/bin/env bats

REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

@test "user plists carry no hardcoded user path" {
  count=$(grep -c '/Users/' "$REPO_DIR/macos/com.snakashima.handy-warm.plist" || true)
  [ "$count" -eq 0 ]
  count=$(grep -c '/Users/' "$REPO_DIR/macos/com.snakashima.secure-input-watch.plist" || true)
  [ "$count" -eq 0 ]
}

@test "install.zsh installs both user LaunchAgents" {
  grep -qF 'com.snakashima.handy-warm' "$REPO_DIR/setup/install.zsh"
  grep -qF 'com.snakashima.secure-input-watch' "$REPO_DIR/setup/install.zsh"
}

@test "plist placeholder substitution produces loadable plist" {
  tmp="$(mktemp -d /private/tmp/plist-test.XXXXXX)"
  sed "s|__DOTFILES__|$REPO_DIR|g" "$REPO_DIR/macos/com.snakashima.handy-warm.plist" > "$tmp/out.plist"
  plutil -lint "$tmp/out.plist"
  grep -qF "$REPO_DIR/bin/handy-warm" "$tmp/out.plist"
  rm -rf "$tmp"
}
