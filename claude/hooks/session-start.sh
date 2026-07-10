#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../skills/handover/scripts/handover-lib.sh"

PROJECT_DIR="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0

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
