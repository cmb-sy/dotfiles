#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../skills/handover/scripts/handover-lib.sh"

PROJECT_DIR="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0

# Another session editing the same working tree is worth knowing before the
# first edit, so this runs before the handover check returns early. Warn only:
# parallel work is not always wrong, and a gate that blocks legitimate work gets
# disabled outright.
PEERS="$("${SCRIPT_DIR}/../../bin/session-peers" 2>/dev/null)" || PEERS=""
if [[ -n "$PEERS" ]]; then
  echo "⚠ この working tree で他の Claude セッションが動いています:"
  printf '%s\n' "$PEERS" | while IFS=$'\t' read -r pane status; do
    printf '    %-10s %s\n' "$pane" "$status"
  done
  echo "  同じファイルを同時に編集しないよう注意してください。"
  echo ""
fi

HANDOVER_BASE="${PROJECT_DIR}/.agents/handover"

[[ -d "$HANDOVER_BASE" ]] || exit 0

SESSIONS="$(scan_sessions "$HANDOVER_BASE")"
SESSION_COUNT="$(echo "$SESSIONS" | jq 'length')"

if [[ "$SESSION_COUNT" -eq 0 ]]; then
  exit 0
fi

echo "📋 Handover sessions found:"
echo "$SESSIONS" | jq -r '.[] | "  - [\(.branch)/\(.fingerprint)] tasks: \(.done_tasks)/\(.total_tasks) | next: \(.next_action)"'
echo ""
echo "Use '/continue' to resume, or start fresh."
