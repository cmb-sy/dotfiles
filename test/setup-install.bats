#!/usr/bin/env bats
# Static checks for setup/install.zsh guard conditions.

REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

# setup.zsh sources install.zsh with FORCE=1, so a `[[ ${FORCE} != 1 ]]` guard
# would skip this block on the one path that installs a fresh Mac. Only CI skips.
# The `^if` anchor rejects a commented-out condition.
@test "macOS settings ブロックは CI だけをスキップし FORCE=1 では適用される" {
  run bash -c "grep -Ec '^if ! util::is_ci && util::confirm \"Apply macOS settings' '$REPO_DIR/setup/install.zsh'"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "install.zsh の条件分岐に FORCE の逆判定が残っていない" {
  run bash -c "grep -Ec 'FORCE\} != 1' '$REPO_DIR/setup/install.zsh'"
  [ "$output" -eq 0 ]
}
