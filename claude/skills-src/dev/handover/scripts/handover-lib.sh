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

scan_sessions() {
  local base_dir="$1"
  base_dir="${base_dir%/}"
  local results="[]"
  local file rel_path fingerprint branch session_status entry

  while IFS= read -r file; do
    [[ -f "$file" ]] || continue
    session_status="$(jq -r '.status // empty' "$file" 2>/dev/null)"
    [[ "$session_status" == "READY" ]] || continue

    rel_path="${file#"$base_dir"/}"
    rel_path="${rel_path%/project-state.json}"
    fingerprint="$(basename "$rel_path")"
    branch="$(dirname "$rel_path")"

    entry="$(jq -c --arg branch "$branch" --arg fingerprint "$fingerprint" '
      {
        branch: $branch,
        fingerprint: $fingerprint,
        done_tasks: ([.active_tasks[]? | select(.status == "done")] | length),
        total_tasks: (.active_tasks | length),
        next_action: (([.active_tasks[]? | select(.status == "in_progress" or .status == "blocked") | .next_action] | first) // "")
      }
    ' "$file" 2>/dev/null)" || continue

    results="$(jq -c --argjson e "$entry" '. + [$e]' <<< "$results")"
  done < <(find "$base_dir" -name project-state.json 2>/dev/null | sort)

  echo "$results"
}
