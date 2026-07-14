#!/bin/bash
# stop-failure-handler.sh — auto-resume Claude Code after a proxy-caused
# mid-stream disconnect.
#
# Why: our corporate FortiGate SSL-inspection proxy actively drops the TCP
# connection mid-stream, surfaced by Claude Code as "API Error: Connection
# closed mid-response." Empirically confirmed (2026-07-14, 3/3 occurrences,
# see stop-failure-debug.log history) that this always fires StopFailure
# with error:"server_error", and that $HERDR_PANE_ID is correctly inherited
# by the hook subprocess and matches the actual pane running the session.
# StopFailure's JSON output does not document support for decision:"block"
# (unlike Stop/PostToolUse/UserPromptSubmit), so this works around that by
# using herdr to type "continue" into the pane, the same as if the user had
# typed it themselves.
#
# Only acts on error == "server_error" (the value observed for this
# failure); other error values (rate_limit, overloaded,
# authentication_failed, etc.) need different handling and are left alone.

INPUT="$(cat)"
LOG="$HOME/.claude/stop-failure-debug.log"

# Keep logging every occurrence for auditing (same format as the earlier
# diagnostic-only version of this hook).
{
  printf '\n=== %s ===\n' "$(date '+%Y-%m-%d %H:%M:%S')"
  printf 'HERDR_PANE_ID=%s\n' "${HERDR_PANE_ID:-<unset>}"
  printf '%s\n' "$INPUT"
} >> "$LOG" 2>/dev/null

# Karabiner (F1) style PATH fix — hooks can run with a minimal launchd/exec
# environment where `herdr`/`jq` aren't resolvable via a bare name.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

ERROR="$(printf '%s' "$INPUT" | jq -r '.error // empty' 2>/dev/null)"
[ "$ERROR" = "server_error" ] || exit 0
[ -n "$HERDR_PANE_ID" ] || exit 0
command -v herdr >/dev/null 2>&1 || exit 0

herdr pane send-text "$HERDR_PANE_ID" "continue" >/dev/null 2>&1
sleep 0.3
herdr pane send-keys "$HERDR_PANE_ID" Enter >/dev/null 2>&1

exit 0
