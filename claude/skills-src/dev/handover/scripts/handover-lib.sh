#!/bin/bash
# Shared functions for claude/hooks/session-start.sh and claude/hooks/post-commit.sh.
# Sourced, not executed directly.

_handover_log() {
  echo "[handover] $*" >&2
}

validate_project_state() {
  local state_file="$1"
  [[ -f "$state_file" ]] || return 1
  jq empty "$state_file" >/dev/null 2>&1 || return 1

  local version
  version="$(jq -r '.version // empty' "$state_file" 2>/dev/null)"
  [[ "$version" == "4" || "$version" == "5" ]] || return 1

  jq -e 'has("status") and has("active_tasks")' "$state_file" >/dev/null 2>&1 || return 1

  return 0
}
