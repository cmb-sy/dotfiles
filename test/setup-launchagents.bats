#!/usr/bin/env bats

load "helpers/common"

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

# The label check above passes on commented-out code, so assert the two lines
# that actually do the work live on non-comment lines.
@test "install.zsh substitutes and bootstraps on live code, not in a comment" {
  code="$(grep -v '^[[:space:]]*#' "$REPO_DIR/setup/install.zsh")"
  echo "$code" | grep -qF 'sed "s|__DOTFILES__|'
  echo "$code" | grep -qF 'launchctl bootstrap "gui/$(id -u)"'
}

@test "plist placeholder substitution produces loadable plists" {
  make_tmpdir
  for name in handy-warm secure-input-watch; do
    out="$TEST_TMPDIR/$name.plist"
    sed "s|__DOTFILES__|$REPO_DIR|g" "$REPO_DIR/macos/com.snakashima.$name.plist" > "$out"
    plutil -lint "$out"
    grep -qF "$REPO_DIR/bin/$name" "$out"
    # A leftover placeholder would launch a nonexistent program every interval.
    placeholders=$(grep -c '__DOTFILES__' "$out" || true)
    [ "$placeholders" -eq 0 ]
  done
  rm -rf "$TEST_TMPDIR"
}
