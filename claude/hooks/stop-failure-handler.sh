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

# Cap consecutive auto-continues at 3. Without this, a persistent network
# outage (e.g. DNS ENOTFOUND) loops forever: every failed turn re-fires
# StopFailure, which types "continue", which fails again. The counter is
# per-pane and reset by stop.sh on any successful (normal) stop.
MAX_CONTINUES=3
COUNT_FILE="$HOME/.claude/stop-failure-continue-${HERDR_PANE_ID//[^A-Za-z0-9_-]/_}.count"
mkdir -p "$(dirname "$COUNT_FILE")" 2>/dev/null
COUNT=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)
case "$COUNT" in (*[!0-9]*|'') COUNT=0;; esac
if [ "$COUNT" -ge "$MAX_CONTINUES" ]; then
  printf 'auto-continue suppressed (limit %s reached)\n' "$MAX_CONTINUES" >> "$LOG" 2>/dev/null
  exit 0
fi
printf '%s' "$((COUNT + 1))" > "$COUNT_FILE" 2>/dev/null

herdr pane send-text "$HERDR_PANE_ID" "continue" >/dev/null 2>&1
sleep 0.3
herdr pane send-keys "$HERDR_PANE_ID" Enter >/dev/null 2>&1

exit 0
