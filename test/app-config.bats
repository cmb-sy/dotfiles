#!/usr/bin/env bats
# Tests for app config, ignore files and public docs.

load "helpers/common"

# Exit 0 when the repo's global gitignore alone ignores $1, 1 when not.
global_ignores() {
  git -C "$TEST_TMPDIR" -c core.excludesfile="$REPO_DIR/.gitignore_global" \
    check-ignore --no-index -q "$1"
}

setup() {
  make_tmpdir
  git -C "$TEST_TMPDIR" init -q -b main
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

@test "global gitignore does not swallow source dirs named lib/build/env/dist" {
  for p in claude/skills/foo/lib/x server/build/x a/env/x a/dist/x a/downloads/x a/eggs/x; do
    run global_ignores "$p"
    [ "$status" -eq 1 ]
  done
}

@test "global gitignore still drops macOS and Python junk" {
  run global_ignores .DS_Store
  [ "$status" -eq 0 ]
  run global_ignores a/__pycache__/x
  [ "$status" -eq 0 ]
  run global_ignores a/venv/x
  [ "$status" -eq 0 ]
}

@test "global gitignore matches the folder-icon file, not a plain Icon" {
  run global_ignores claude/skills/foo/Icon
  [ "$status" -eq 1 ]
  run global_ignores "a/Icon"$'\r'
  [ "$status" -eq 0 ]
  run global_ignores a/Iconr
  [ "$status" -eq 1 ]
}

@test "Handy prompt does not override the glossary's 一周 mapping" {
  count=$(grep -c '一周' "$REPO_DIR/handy/ja_light_tidy.prompt.txt" || true)
  [ "$count" -eq 0 ]
  grep -qF '一周→issue' "$REPO_DIR/handy/glossary.txt"
}

@test "Handy settings script does not assume a whisper model" {
  count=$(grep -ci 'whisper' "$REPO_DIR/handy/apply-settings.py" || true)
  [ "$count" -eq 0 ]
}

@test "tracked files carry no internal network details" {
  # Built by concatenation so this file does not match itself.
  pat='advantage''group|forti''client|\b10\.[0-9]+\.[0-9]+\.[0-9]+\b'
  count=$(git -C "$REPO_DIR" grep -c -i -E "$pat" | wc -l | tr -d ' ')
  [ "$count" -eq 0 ]
}

@test "caps-lock debug note is no longer tracked" {
  count=$(git -C "$REPO_DIR" ls-files docs/debug | wc -l | tr -d ' ')
  [ "$count" -eq 0 ]
  count=$(grep -c 'caps-lock-rogue' "$REPO_DIR/.gitignore" "$REPO_DIR/bin/voice-out" | grep -cv ':0$' || true)
  [ "$count" -eq 0 ]
}

@test "unused Ghostty background and cmux tap are gone" {
  [ ! -e "$REPO_DIR/terminal/ghostty/background.png" ]
  [ ! -e "$REPO_DIR/terminal/ghostty/make-background.py" ]
  count=$(grep -c 'manaflow-ai/cmux' "$REPO_DIR/Brewfile" || true)
  [ "$count" -eq 0 ]
}
