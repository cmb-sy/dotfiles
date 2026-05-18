#!/bin/bash
set -euo pipefail

MESSAGE="${1:?Usage: notify.sh MESSAGE TITLE TYPE}"
TITLE="${2:?Usage: notify.sh MESSAGE TITLE TYPE}"
TYPE="${3:?Usage: notify.sh MESSAGE TITLE TYPE}"

# Icon and timeout per notification type
case "$TYPE" in
  idle)       ICON="✅"; TIMEOUT=5000 ;;
  permission) ICON="🔐"; TIMEOUT=0    ;;
  question)   ICON="💬"; TIMEOUT=0    ;;
  *)          ICON="📢"; TIMEOUT=5000 ;;
esac

DISPLAY_TITLE="${ICON} ${TITLE}"

# Trigger WezTerm toast_notification via user-var escape sequence
VALUE="$(printf '%s\t%s\t%s' "$DISPLAY_TITLE" "$MESSAGE" "$TIMEOUT")"
ENCODED="$(printf '%s' "$VALUE" | base64)"
ESCAPE_SEQ="$(printf "\033]1337;SetUserVar=%s=%s\007" "claude_notify" "$ENCODED")"

if (printf '%s' "$ESCAPE_SEQ" > /dev/tty) 2>/dev/null; then
  : # Successfully sent to WezTerm toast_notification
else
  # Fallback to osascript when TTY is unavailable
  osascript -e "display notification \"$MESSAGE\" with title \"$DISPLAY_TITLE\""
fi
