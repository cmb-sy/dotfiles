#!/usr/bin/env bats
# test/voice-lib.bats — the shared voice helpers must be the single definition.

load "helpers/common"

@test "voice lib defines the handy settings path once" {
  grep -qF 'com.pais.handy/settings_store.json' "$REPO_DIR/bin/lib/voice.sh"
}

@test "no voice script hardcodes the handy settings path anymore" {
  hits=$(grep -rlF 'com.pais.handy/settings_store.json' "$REPO_DIR/bin" \
    | grep -cv '^.*/bin/lib/voice.sh$') || hits=0
  [ "$hits" -eq 0 ]
}

@test "no voice script open-codes the handy process check anymore" {
  hits=$(grep -rlF 'pgrep -x handy' "$REPO_DIR/bin" \
    | grep -cv '^.*/bin/lib/voice.sh$') || hits=0
  [ "$hits" -eq 0 ]
}

@test "handy_running reports true when the process check succeeds" {
  make_tmpdir
  printf '#!/bin/bash\nexit 0\n' > "$TEST_TMPDIR/pgrep"
  chmod +x "$TEST_TMPDIR/pgrep"
  run bash -c "PATH='$TEST_TMPDIR:$PATH'; . '$REPO_DIR/bin/lib/voice.sh'; handy_running && echo YES"
  [ "$output" = "YES" ]
  rm -rf "$TEST_TMPDIR"
}

@test "handy_running reports false when the process is absent" {
  make_tmpdir
  printf '#!/bin/bash\nexit 1\n' > "$TEST_TMPDIR/pgrep"
  chmod +x "$TEST_TMPDIR/pgrep"
  run bash -c "PATH='$TEST_TMPDIR:$PATH'; . '$REPO_DIR/bin/lib/voice.sh'; handy_running || echo NO"
  [ "$output" = "NO" ]
  rm -rf "$TEST_TMPDIR"
}

@test "the voice lib is tracked by git" {
  # The global gitignore drops lib/ as build output, so an un-negated bin/lib
  # would be skipped by `git add` and break every voice script on a fresh clone.
  git -C "$REPO_DIR" ls-files --error-unmatch bin/lib/voice.sh
}

@test "the lib is POSIX-sourceable from both bash and zsh" {
  run bash -c ". '$REPO_DIR/bin/lib/voice.sh' && echo OK"
  [ "$output" = "OK" ]
  run zsh -c ". '$REPO_DIR/bin/lib/voice.sh' && echo OK"
  [ "$output" = "OK" ]
}
