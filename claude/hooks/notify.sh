#!/bin/bash
# Bell + macOS notification + cmux notification for one message.
set -euo pipefail

MESSAGE="${1:-Claude Code}"
TITLE="Claude Code"
CMUX_SOCK="${HOME}/Library/Application Support/cmux/cmux.sock"

# osascript takes one AppleScript string, so quotes in the message must escape.
escaped="${MESSAGE//\\/\\\\}"
escaped="${escaped//\"/\\\"}"

printf '\a' > /dev/tty 2>/dev/null || true
osascript -e "display notification \"${escaped}\" with title \"${TITLE}\"" \
  >/dev/null 2>&1 || true
if [ -S "$CMUX_SOCK" ]; then
  cmux notify --title "$TITLE" --body "$MESSAGE" >/dev/null 2>&1 || true
fi
