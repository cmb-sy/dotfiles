#!/bin/bash
set -euo pipefail

readonly HANDOVER_LOG_PREFIX="[claude-post-commit]"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../skills/handover/scripts/handover-lib.sh"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"
if [[ -z "$PROJECT_DIR" ]]; then
  PROJECT_DIR="$(git rev-parse --show-toplevel 2>/dev/null)" || true
fi
if [[ -z "$PROJECT_DIR" ]]; then
  _handover_log "not in a git repository, skipping"
  exit 0
fi

SESSION_DIR="$(find_active_session_dir "$PROJECT_DIR")" || {
  _handover_log "no active handover session found, skipping"
  exit 0
}

STATE_FILE="${SESSION_DIR}/project-state.json"
HANDOVER_FILE="${SESSION_DIR}/handover.md"

if ! validate_project_state "$STATE_FILE"; then
  _handover_log "invalid project-state.json, skipping"
  exit 0
fi

COMMIT_SHA="$(git -C "$PROJECT_DIR" log -1 --format='%H' 2>/dev/null)" || {
  _handover_log "failed to get commit SHA"
  exit 0
}
COMMIT_SHORT="$(echo "$COMMIT_SHA" | cut -c1-7)"
COMMIT_MSG="$(git -C "$PROJECT_DIR" log -1 --format='%s' 2>/dev/null)" || true

if git -C "$PROJECT_DIR" rev-parse HEAD~1 &>/dev/null; then
  FILES_CHANGED_RAW="$(git -C "$PROJECT_DIR" diff --name-only HEAD~1..HEAD 2>/dev/null)" || true
else
  FILES_CHANGED_RAW="$(git -C "$PROJECT_DIR" diff --name-only HEAD 2>/dev/null)" || true
fi

FILES_CHANGED_JSON="$(echo "$FILES_CHANGED_RAW" | jq -R -s '[split("\n")[] | select(length > 0)]')"

NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

{
  add_architecture_change "$STATE_FILE" "$COMMIT_SHORT" "$COMMIT_MSG" "$FILES_CHANGED_JSON" "$NOW" &&
  touch_related_tasks "$STATE_FILE" "$FILES_CHANGED_JSON" "$NOW" &&
  update_status_field "$STATE_FILE"
} || {
  _handover_log "failed to update project-state.json, skipping"
  exit 0
}

generate_handover_md "$STATE_FILE" "$HANDOVER_FILE" || {
  _handover_log "failed to generate handover.md, skipping"
  exit 0
}

_handover_log "updated project-state.json and handover.md for commit ${COMMIT_SHORT}"
