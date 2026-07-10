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

find_active_session_dir() {
  local project_dir="$1"
  local branch handover_dir
  branch="$(git -C "$project_dir" rev-parse --abbrev-ref HEAD 2>/dev/null)" || return 1
  handover_dir="${project_dir}/.agents/handover/${branch}"
  [[ -d "$handover_dir" ]] || return 1

  local fingerprint session_dir state_file session_status
  while IFS= read -r fingerprint; do
    session_dir="${handover_dir}/${fingerprint}"
    state_file="${session_dir}/project-state.json"
    [[ -f "$state_file" ]] || continue
    session_status="$(jq -r '.status // empty' "$state_file" 2>/dev/null)"
    if [[ "$session_status" == "READY" ]]; then
      echo "$session_dir"
      return 0
    fi
  done < <(ls -1 "$handover_dir" 2>/dev/null | sort -r)

  return 1
}

add_architecture_change() {
  local state_file="$1" sha="$2" summary="$3" files_json="$4" timestamp="$5"
  local tmp
  tmp="$(mktemp)"
  jq --arg sha "$sha" --arg summary "$summary" --argjson files "$files_json" --arg date "$timestamp" '
    .architecture_changes = ((.architecture_changes // []) + [{
      commit_sha: $sha,
      summary: $summary,
      files_changed: $files,
      date: $date
    }])
  ' "$state_file" > "$tmp" && mv "$tmp" "$state_file"
}

touch_related_tasks() {
  local state_file="$1" files_json="$2" timestamp="$3"
  local tmp
  tmp="$(mktemp)"
  jq --argjson changed "$files_json" --arg date "$timestamp" '
    .active_tasks = [
      .active_tasks[]? |
      ((.file_paths // []) | any(. as $p | $changed | index($p) != null)) as $matched |
      if $matched then .last_touched = $date else . end
    ]
  ' "$state_file" > "$tmp" && mv "$tmp" "$state_file"
}

update_status_field() {
  local state_file="$1"
  local tmp
  tmp="$(mktemp)"
  jq '
    .status = (
      if ((.active_tasks // []) | length > 0) and ((.active_tasks // []) | all(.status == "done"))
      then "ALL_COMPLETE"
      else "READY"
      end
    )
  ' "$state_file" > "$tmp" && mv "$tmp" "$state_file"
}

generate_handover_md() {
  local state_file="$1" output_path="$2"
  local now session_id session_status
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  session_id="$(jq -r '.session_id // "unknown"' "$state_file")"
  session_status="$(jq -r '.status // "READY"' "$state_file")"

  {
    echo "# Session Handover"
    echo "> Generated: ${now}"
    echo "> Session: ${session_id}"
    echo "> Status: ${session_status}"
    echo ""
    echo "## Completed"
    jq -r '.active_tasks[]? | select(.status == "done") | "- [\(.id)] \(.description) (\(.commit_sha // "unknown"))"' "$state_file"
    echo ""
    echo "## Remaining"
    jq -r '.active_tasks[]? | select(.status == "in_progress" or .status == "blocked") | "- [\(.id)] **\(.status)** \(.description)\n  - files: \((.file_paths // []) | join(", "))\n  - next: \(.next_action // "")"' "$state_file"
    echo ""
    echo "## Blockers"
    jq -r '.active_tasks[]? | (.blockers // [])[] | "- \(.)"' "$state_file"
    echo ""
    echo "## Context"
    jq -r '.recent_decisions[]? | "- \(.decision)（理由: \(.rationale)）"' "$state_file"
    echo ""
    echo "## Architecture Changes (Recent)"
    jq -r '.architecture_changes[]? | "- \(.commit_sha): \(.summary)"' "$state_file"
    echo ""
    echo "## Known Issues"
    jq -r '.known_issues[]? | "- [\(.severity)] \(.description)"' "$state_file"
  } > "$output_path"
}
