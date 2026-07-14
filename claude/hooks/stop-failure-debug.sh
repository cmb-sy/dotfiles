#!/bin/bash
# stop-failure-debug.sh — diagnostic logger for the StopFailure hook.
#
# Why this hook was added: our corporate FortiGate SSL-inspection proxy
# actively drops the TCP connection mid-stream, which Claude Code surfaces
# as "API Error: Connection closed mid-response." Binary inspection of the
# installed Claude Code CLI confirmed this path sets `error: "server_error"`
# on the message and calls executeStopFailureHooks — so StopFailure does
# fire for this case, with a JSON payload shaped like
# {hook_event_name:"StopFailure", error:"server_error", ...}.
# This script only logs (timestamp + $HERDR_PANE_ID + raw stdin) to confirm
# that shape empirically before wiring up the real fix: once confirmed,
# replace this logger with a command that checks `error == "server_error"`
# and uses `herdr pane send-text` to auto-type "continue" into the pane,
# working around the fact that StopFailure's JSON output does not document
# support for `decision: "block"` the way Stop/PostToolUse/UserPromptSubmit do.
#
# Log file: ~/.claude/stop-failure-debug.log (grows unbounded, delete manually)

LOG="$HOME/.claude/stop-failure-debug.log"
INPUT="$(cat)"

{
  printf '\n=== %s ===\n' "$(date '+%Y-%m-%d %H:%M:%S')"
  printf 'HERDR_PANE_ID=%s\n' "${HERDR_PANE_ID:-<unset>}"
  printf '%s\n' "$INPUT"
} >> "$LOG" 2>/dev/null

exit 0
