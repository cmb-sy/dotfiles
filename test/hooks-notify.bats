#!/usr/bin/env bats
# notify.sh の実挙動と settings.json 側の配線テスト。

load "helpers/common"

@test "notify.sh exists and is executable" {
  [ -x "$REPO_DIR/claude/hooks/notify.sh" ]
}

@test "notify.sh passes its argument through to the notification" {
  make_tmpdir
  printf '#!/bin/bash\necho "osascript: $*" >> "%s/calls"\n' "$TEST_TMPDIR" > "$TEST_TMPDIR/osascript"
  printf '#!/bin/bash\necho "cmux: $*" >> "%s/calls"\n' "$TEST_TMPDIR" > "$TEST_TMPDIR/cmux"
  chmod +x "$TEST_TMPDIR/osascript" "$TEST_TMPDIR/cmux"
  PATH="$TEST_TMPDIR:$PATH" "$REPO_DIR/claude/hooks/notify.sh" "Task completed" >/dev/null 2>&1
  run cat "$TEST_TMPDIR/calls"
  printf '%s' "$output" | grep -qF 'Task completed'
  rm -rf "$TEST_TMPDIR"
}

@test "notify.sh survives a missing notifier" {
  make_tmpdir
  run env PATH="$TEST_TMPDIR" "$REPO_DIR/claude/hooks/notify.sh" "Task completed"
  [ "$status" -eq 0 ]
  rm -rf "$TEST_TMPDIR"
}

@test "settings.json calls notify.sh instead of inlining the notification" {
  inline=$(grep -cF 'display notification' "$REPO_DIR/claude/settings.json") || inline=0
  [ "$inline" -eq 0 ]
  grep -qF 'notify.sh' "$REPO_DIR/claude/settings.json"
}

@test "pii-guard is registered once with a combined matcher" {
  hits=$(grep -cF 'pii-guard.py' "$REPO_DIR/claude/settings.json") || hits=0
  [ "$hits" -eq 1 ]
  jq -e '.hooks.PreToolUse[] | select(.hooks[].command | contains("pii-guard"))
         | select(.matcher == "Write|Edit|Bash")' "$REPO_DIR/claude/settings.json"
}

@test "hook commands reference HOME as \${HOME} only" {
  # Bare $HOME/ and ~/ paths; the destructive-command regex mentions $HOME
  # without a slash, so it is not a path reference.
  legacy=$(jq -r '[.hooks[][].hooks[].command, .statusLine.command]
                  | map(select(test("[$]HOME/|~/")))
                  | length' "$REPO_DIR/claude/settings.json")
  [ "$legacy" -eq 0 ]
}

@test "settings.json stays valid JSON" {
  run jq empty "$REPO_DIR/claude/settings.json"
  [ "$status" -eq 0 ]
}
