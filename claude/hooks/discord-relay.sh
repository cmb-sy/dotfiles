#!/bin/bash
# Append one line per Claude Code event to a local spool. bin/discord-relay-flush
# posts them to Discord later.
#
# This never touches the network. Discord's webhook allows 5 requests per 2
# seconds and PostToolUse fires on every tool, so posting from here would both
# blow the limit and put a network round trip in front of every tool call.
#
# Deny by default: a repository missing from the allowlist produces no line at
# all. A denylist would leak any repository created before someone remembered to
# list it, and these lines carry paths, commands and tool arguments. The
# allowlist lives outside the repo so adding a work remote does not publish its
# name in a public repo.
#
# Never exits non-zero: a broken relay must not block Claude.

INPUT="$(cat)"

# Hooks can run with a minimal environment where bare names do not resolve.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

ALLOWLIST="${DISCORD_RELAY_ALLOWLIST:-$HOME/.config/discord-relay/allowlist}"
SPOOL="${DISCORD_RELAY_SPOOL:-$HOME/.local/state/discord-relay/spool}"
LABEL="${1:-}"

# Early exit, not a guard: the grep below already refuses a missing allowlist.
# This runs on every tool call, so it is here to avoid spawning git for users
# who never configured the relay. Removing it changes no behaviour, which is
# why no test pins it -- keep it for the cost, not the correctness.
[ -f "$ALLOWLIST" ] || exit 0

remote="$(git -C "${CLAUDE_PROJECT_DIR:-$PWD}" remote get-url origin 2>/dev/null)"
[ -n "$remote" ] || exit 0
grep -qxF "$remote" "$ALLOWLIST" 2>/dev/null || exit 0

event="$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)"
[ -n "$event" ] || exit 0

if [ "$event" = "PostToolUse" ]; then
  detail="$(printf '%s' "$INPUT" | jq -r '.tool_name // "?"' 2>/dev/null)"
else
  detail="${LABEL:-$event}"
fi
[ -n "$detail" ] || detail="$event"

pane="${HERDR_PANE_ID:-no-pane}"
[ -n "$pane" ] || pane="no-pane"

mkdir -p "${SPOOL%/*}" 2>/dev/null
# Tabs delimit the fields, so strip any the payload carries.
printf '%s\t%s\t%s\n' \
  "$(printf '%s' "$pane"   | tr '\t' ' ')" \
  "$(printf '%s' "$event"  | tr '\t' ' ')" \
  "$(printf '%s' "$detail" | tr '\t' ' ')" >> "$SPOOL" 2>/dev/null

exit 0
