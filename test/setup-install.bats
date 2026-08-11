#!/usr/bin/env bats
# Static checks for setup/install.zsh guard conditions.

load "helpers/common"

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

# The python step is what keeps the pygments/pyyaml skips from being permanent,
# and the skip messages point at it by name -- so deleting it must fail here.
# Assert on live code, not on comments.
@test "install.zsh は python パッケージを uv で導入する" {
  code=$(grep -v '^[[:space:]]*#' "$REPO_DIR/setup/install.zsh")
  printf '%s' "$code" | grep -qF 'uv pip install'
  printf '%s' "$code" | grep -qF 'pygments pyyaml'
}

# uv against the Xcode CLT interpreter either fails on permissions or writes to
# a tree that a CLT update wipes; both leave the tests skipping forever.
@test "install.zsh は CLT の python3 を拒否する" {
  code=$(grep -v '^[[:space:]]*#' "$REPO_DIR/setup/install.zsh")
  printf '%s' "$code" | grep -qF '/usr/bin/python3'
  printf '%s' "$code" | grep -qF '/Library/Developer/'
}

# The pin only takes effect if the runtimes are actually installed, and it must
# happen before the python step chooses an interpreter.
@test "mise install は python ステップより前に走る" {
  code=$(grep -v '^[[:space:]]*#' "$REPO_DIR/setup/install.zsh")
  # Anchor on the start of the command so `true # mise install` does not pass.
  printf '%s\n' "$code" | grep -qE '^[[:space:]]*mise install'
  mise_at=$(printf '%s\n' "$code" | grep -nE '^[[:space:]]*mise install' | head -1 | cut -d: -f1)
  py_at=$(printf '%s\n' "$code" | grep -nE '^[[:space:]]*uv pip install' | head -1 | cut -d: -f1)
  [ "$mise_at" -lt "$py_at" ]
}

# The interpreter the repo assumes must be pinned in-repo: without this file the
# version comes from an unmanaged ~/.config/mise/config.toml.
@test "mise 設定がリポジトリで python を固定している" {
  grep -qF 'python = ' "$REPO_DIR/setup/mise-config.toml"
}
