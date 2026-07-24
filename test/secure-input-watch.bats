#!/usr/bin/env bats
# Tests for bin/secure-input-watch Ghostty toggle auto-remediation.
# External binaries are injected via *_BIN env vars pointing at stubs.

setup() {
  TEST_DIR="$(mktemp -d /private/tmp/siw-test.XXXXXX)"
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME/.cache" "$TEST_DIR/stubs"
  STATE_FILE="$HOME/.cache/secure-input-watch.state"
  SCRIPT="$BATS_TEST_DIRNAME/../bin/secure-input-watch"

  # swift stub: prints PID from swift_output file (call-count aware:
  # line N of the file is the output for call N; last line repeats).
  cat > "$TEST_DIR/stubs/swift" <<'EOF'
#!/bin/bash
count_file="$STUB_DIR/swift_calls"
n=$(( $(cat "$count_file" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$count_file"
total=$(wc -l < "$STUB_DIR/swift_output" | tr -d ' ')
line=$n; [ "$line" -gt "$total" ] && line=$total
sed -n "${line}p" "$STUB_DIR/swift_output"
EOF

  # osascript stub: logs args; UI click succeeds/fails per click_exit file.
  cat > "$TEST_DIR/stubs/osascript" <<'EOF'
#!/bin/bash
echo "$*" >> "$STUB_DIR/osascript_calls"
case "$*" in
  *"click menu item"*) exit "$(cat "$STUB_DIR/click_exit" 2>/dev/null || echo 0)" ;;
esac
exit 0
EOF

  # defaults stub: logs args; read returns content of defaults_value file.
  cat > "$TEST_DIR/stubs/defaults" <<'EOF'
#!/bin/bash
echo "$*" >> "$STUB_DIR/defaults_calls"
if [ "$1" = "read" ]; then
  cat "$STUB_DIR/defaults_value" 2>/dev/null || { echo "missing" >&2; exit 1; }
fi
exit 0
EOF

  # ps stub: prints command path from ps_output file.
  cat > "$TEST_DIR/stubs/ps" <<'EOF'
#!/bin/bash
cat "$STUB_DIR/ps_output"
EOF

  chmod +x "$TEST_DIR/stubs/"*
  export STUB_DIR="$TEST_DIR/stubs"
  export SWIFT_BIN="$STUB_DIR/swift"
  export OSASCRIPT_BIN="$STUB_DIR/osascript"
  export DEFAULTS_BIN="$STUB_DIR/defaults"
  export PS_BIN="$STUB_DIR/ps"
  export SLEEP_BIN="/usr/bin/true"

  echo "/Applications/Ghostty.app/Contents/MacOS/ghostty" > "$STUB_DIR/ps_output"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "toggle case: click succeeds -> released, notified, state cleared" {
  printf '845\n\n' > "$STUB_DIR/swift_output"   # held, then released after click
  echo "1" > "$STUB_DIR/defaults_value"
  echo "0" > "$STUB_DIR/click_exit"
  touch "$STATE_FILE"

  run "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qF "click menu item" "$STUB_DIR/osascript_calls"
  grep -qF "display notification" "$STUB_DIR/osascript_calls"
  grep "display notification" "$STUB_DIR/osascript_calls" | grep -qF "自動"
  [ ! -f "$STATE_FILE" ]
}

@test "toggle case: click fails -> defaults write fallback, falls through to timer" {
  printf '845\n845\n' > "$STUB_DIR/swift_output"  # still held after click attempt
  echo "1" > "$STUB_DIR/defaults_value"
  echo "1" > "$STUB_DIR/click_exit"

  run "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qF "write com.mitchellh.ghostty SecureInput -bool false" "$STUB_DIR/defaults_calls"
  # falls through: state file written with tracked pid
  grep -qF " 845 " "$STATE_FILE"
}

@test "10480 case: Ghostty holds but pref=0 -> no auto-fix, timer path only" {
  printf '845\n' > "$STUB_DIR/swift_output"
  echo "0" > "$STUB_DIR/defaults_value"

  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -f "$STUB_DIR/osascript_calls" ] || ! grep -qF "click menu item" "$STUB_DIR/osascript_calls"
  grep -qF " 845 " "$STATE_FILE"
}

@test "non-Ghostty holder: no auto-fix even if pref=1" {
  printf '999\n' > "$STUB_DIR/swift_output"
  echo "/Applications/Terminal.app/Contents/MacOS/Terminal" > "$STUB_DIR/ps_output"
  echo "1" > "$STUB_DIR/defaults_value"

  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -f "$STUB_DIR/osascript_calls" ] || ! grep -qF "click menu item" "$STUB_DIR/osascript_calls"
  grep -qF " 999 " "$STATE_FILE"
}

@test "not held: state cleared, nothing invoked" {
  printf '\n' > "$STUB_DIR/swift_output"
  echo "1" > "$STUB_DIR/defaults_value"
  touch "$STATE_FILE"

  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -f "$STATE_FILE" ]
  [ ! -f "$STUB_DIR/osascript_calls" ]
}

@test "threshold notification still fires for non-toggle case" {
  printf '845\n' > "$STUB_DIR/swift_output"
  echo "0" > "$STUB_DIR/defaults_value"
  old=$(( $(date +%s) - 200 ))
  printf '%s 845 0\n' "$old" > "$STATE_FILE"

  run "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qF "display notification" "$STUB_DIR/osascript_calls"
  grep -qF " 845 1" "$STATE_FILE"
}
