#!/usr/bin/env bats
# test/voice-lib.bats — the shared voice helpers must be the single definition.

load "helpers/common"

# The scripts that source bin/lib/voice.sh. Scans below assert on this list
# rather than on all of bin/, so unrelated scripts (bin/view-html greps for its
# own process) do not read as offenders.
VOICE_SCRIPTS="voice-switch voice-toggle voice-out handy-warm secure-input-watch ai-format"

voice_script_paths() {
  for name in $VOICE_SCRIPTS; do printf '%s\n' "$REPO_DIR/bin/$name"; done
}

@test "every voice script is where the scans expect it" {
  # Positive control: a wrong path here would make the grep scans below find
  # nothing and pass for the wrong reason.
  found=$(voice_script_paths | xargs ls | wc -l | tr -d ' ')
  [ "$found" -eq 6 ]
}

@test "the handy settings path is written exactly once, in the lib" {
  [ "$(grep -cF 'com.pais.handy/settings_store.json' "$REPO_DIR/bin/lib/voice.sh")" -eq 1 ]
  offenders=$(voice_script_paths | xargs grep -lF 'com.pais.handy' | wc -l | tr -d ' ')
  [ "$offenders" -eq 0 ]
}

@test "the pgrep binary is named exactly once, in the lib" {
  [ "$(grep -cF '/usr/bin/pgrep' "$REPO_DIR/bin/lib/voice.sh")" -eq 1 ]
  offenders=$(voice_script_paths | xargs grep -l 'pgrep' | wc -l | tr -d ' ')
  [ "$offenders" -eq 0 ]
}

@test "handy_running reports true when the process check succeeds" {
  make_tmpdir
  printf '#!/bin/bash\nexit 0\n' > "$TEST_TMPDIR/pgrep"
  chmod +x "$TEST_TMPDIR/pgrep"
  run bash -c "PGREP_BIN='$TEST_TMPDIR/pgrep'; . '$REPO_DIR/bin/lib/voice.sh'; handy_running && echo YES"
  [ "$output" = "YES" ]
  rm -rf "$TEST_TMPDIR"
}

@test "handy_running reports false when the process is absent" {
  make_tmpdir
  printf '#!/bin/bash\nexit 1\n' > "$TEST_TMPDIR/pgrep"
  chmod +x "$TEST_TMPDIR/pgrep"
  run bash -c "PGREP_BIN='$TEST_TMPDIR/pgrep'; . '$REPO_DIR/bin/lib/voice.sh'; handy_running || echo NO"
  [ "$output" = "NO" ]
  rm -rf "$TEST_TMPDIR"
}

@test "pgrep defaults to the absolute path for the minimal launchd env" {
  run bash -c ". '$REPO_DIR/bin/lib/voice.sh'; printf '%s' \"\$PGREP_BIN\""
  [ "$output" = "/usr/bin/pgrep" ]
}

@test "the lib refuses to build the settings path from an empty HOME" {
  # Without this, HANDY_SETTINGS becomes /Library/... and bin/handy-warm reads
  # the miss as "Handy has not written settings yet".
  # Not `run`: a sourced ${HOME:?} aborts the shell with 127, which `run`
  # reports as a command-not-found warning.
  status=0
  out=$(env -u HOME bash -c ". '$REPO_DIR/bin/lib/voice.sh'" 2>&1) || status=$?
  [ "$status" -ne 0 ]
  printf '%s' "$out" | grep -qF 'HOME is not set'
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
