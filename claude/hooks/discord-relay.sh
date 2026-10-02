#!/bin/bash
# Append one line per Claude Code event to a local spool. bin/discord-relay-flush
# posts them to Discord later. Wired to Notification and Stop only.
#
# This never touches the network: Discord's webhook allows 5 requests per 2
# seconds, so the flush batches lines instead.
#
# Deny by default: a repository missing from the allowlist produces no line at
# all. A denylist would leak any repository created before someone remembered to
# list it, and these lines say what the session is doing. The
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
# It avoids spawning git for users who never configured the relay. Removing it
# changes no behaviour, which is why no test pins it.
[ -f "$ALLOWLIST" ] || exit 0

remote="$(git -C "${CLAUDE_PROJECT_DIR:-$PWD}" remote get-url origin 2>/dev/null)"
[ -n "$remote" ] || exit 0
grep -qxF "$remote" "$ALLOWLIST" 2>/dev/null || exit 0

event="$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)"
[ -n "$event" ] || exit 0

detail="${LABEL:-$event}"

pane="${HERDR_PANE_ID:-no-pane}"
[ -n "$pane" ] || pane="no-pane"

mkdir -p "${SPOOL%/*}" 2>/dev/null
# Tabs delimit the fields, so strip any the payload carries.
printf '%s\t%s\t%s\n' \
  "$(printf '%s' "$pane"   | tr '\t' ' ')" \
  "$(printf '%s' "$event"  | tr '\t' ' ')" \
  "$(printf '%s' "$detail" | tr '\t' ' ')" >> "$SPOOL" 2>/dev/null

exit 0
