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
# and the skip messages point at it by name, so deleting it has to fail here.
# uv against the Xcode CLT interpreter either fails on permissions or writes to
# a tree that a CLT update wipes; both leave the tests skipping forever.
#
# Run the block rather than grepping for its paths: a presence check passes even
# when the condition is inverted. The block is extracted by heading so the test
# exercises live code, `uv` and `mise` are stubbed, and the interpreter under
# test is whatever the mise stub prints.

# BATS_TEST_TMPDIR, not make_tmpdir: `run` executes this in a subshell, so a
# directory exported from here never reaches the test body that would remove it.
# bats cleans its own per-test directory. It sits under /var/folders rather than
# /private/tmp, which is fine here: the helper issues no rm of its own, and the
# /private/tmp rule exists for commands that do.
run_python_block() {  # $1 = what `mise which python3` should return
  local stub="$BATS_TEST_TMPDIR/stub"
  mkdir -p "$stub"
  printf '#!/bin/bash\n[ "$1" = which ] && echo "%s"\nexit 0\n' "$1" > "$stub/mise"
  printf '#!/bin/bash\necho "UV CALLED: $*"\n' > "$stub/uv"
  chmod +x "$stub/mise" "$stub/uv"
  # util::confirm returns 0 under CI, so the block runs without a prompt.
  awk '/^# Python packages/{f=1} f' "$REPO_DIR/setup/install.zsh" \
    | awk '/^fi$/{print; exit} {print}' > "$BATS_TEST_TMPDIR/block.zsh"
  # PATH is prepended inside the command: .zshenv runs first for `zsh -c` and
  # would otherwise put the real mise ahead of the stub.
  CI=true zsh -c "
    PATH='$stub':\$PATH
    source '$REPO_DIR/setup/util.zsh'
    source '$BATS_TEST_TMPDIR/block.zsh'
  "
}

@test "install.zsh は CLT の python3 を拒否する" {
  run run_python_block /usr/bin/python3
  printf '%s' "$output" | grep -qF 'Xcode CLT'
  called=$(printf '%s' "$output" | grep -cF 'UV CALLED') || called=0
  [ "$called" -eq 0 ]
}

@test "install.zsh は Homebrew の python3 を拒否する" {
  run run_python_block /opt/homebrew/bin/python3
  printf '%s' "$output" | grep -qF 'externally managed'
  called=$(printf '%s' "$output" | grep -cF 'UV CALLED') || called=0
  [ "$called" -eq 0 ]
}

@test "install.zsh は mise の python3 には uv で導入する" {
  run run_python_block "$HOME/.local/share/mise/installs/python/3.13.9/bin/python3"
  printf '%s' "$output" | grep -qF 'UV CALLED'
  printf '%s' "$output" | grep -qF 'pygments pyyaml'
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
