#!/usr/bin/env bash
# doc-audit.sh: Document audit script
# Has 5 types of detection capabilities and outputs results in JSON
# Compatible with bash 3.2+ (macOS)
#
# Prerequisites:
#   - doc-utils.sh (parse_depends_on, match_glob, extract_md_links, _relpath) must be available
#   - Uses macOS date command (-r <timestamp>)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../doc-check/scripts/lib/doc-utils.sh"

# --- JSON helpers ---
# JSON escape without jq dependency
_json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

# --- 1. check_broken_deps ---
# Check if paths declared in depends-on exist
# For glob patterns, use find + match_glob to check if at least one match exists
# Returns JSON array: [{"doc":"path","missing":"path"}]
check_broken_deps() {
  local repo_root="$1"
  local results=""
  local first=true

  while IFS= read -r md_file; do
    local deps
    deps=$(parse_depends_on "$md_file")
    [[ -z "$deps" ]] && continue

    local rel_doc
    rel_doc=$(_relpath "$md_file" "$repo_root")

    while IFS= read -r dep; do
      [[ -z "$dep" ]] && continue

      # Determine if it's a glob pattern (contains *, ?, **)
      if [[ "$dep" == *'*'* ]] || [[ "$dep" == *'?'* ]]; then
        # glob: enumerate files with find and check if at least one matches via match_glob
        local found=false
        while IFS= read -r candidate; do
          local rel_candidate
          rel_candidate=$(_relpath "$candidate" "$repo_root")
          if match_glob "$dep" "$rel_candidate"; then
            found=true
            break
          fi
        done < <(find "$repo_root" -type f -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null)
        if [[ "$found" == false ]]; then
          [[ "$first" == true ]] && first=false || results="${results},"
          results="${results}{\"doc\":\"$(_json_escape "$rel_doc")\",\"missing\":\"$(_json_escape "$dep")\"}"
        fi
      else
        # Concrete path: check existence
        if [[ ! -e "${repo_root}/${dep}" ]]; then
          [[ "$first" == true ]] && first=false || results="${results},"
          results="${results}{\"doc\":\"$(_json_escape "$rel_doc")\",\"missing\":\"$(_json_escape "$dep")\"}"
        fi
      fi
    done <<< "$deps"
  done < <(find "$repo_root" -name '*.md' -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null)

  printf '[%s]' "$results"
}

# --- 2. check_dead_links ---
# Check if markdown link targets in all md file bodies exist
# JSON array: [{"doc":"path","link":"path","line":N}]
check_dead_links() {
  local repo_root="$1"
  local results=""
  local first=true

  while IFS= read -r md_file; do
    local rel_doc
    rel_doc=$(_relpath "$md_file" "$repo_root")
    local dir
    dir="$(dirname "$md_file")"

    # Extract links with line numbers (using process substitution to avoid subshell)
    local awk_output
    awk_output=$(awk '
      BEGIN { in_fm=0 }
      NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
      in_fm && /^---[[:space:]]*$/ { in_fm=0; next }
      !in_fm {
        line = $0
        while (match(line, /\[[^\]]*\]\(([^)]+)\)/)) {
          link_start = RSTART
          link_len = RLENGTH
          link_text = substr(line, link_start, link_len)
          paren_start = index(link_text, "(")
          link_target = substr(link_text, paren_start + 1, length(link_text) - paren_start - 1)
          anchor_pos = index(link_target, "#")
          if (anchor_pos > 0) link_target = substr(link_target, 1, anchor_pos - 1)
          if (link_target !~ /^#/ && link_target !~ /^https?:\/\//) {
            print NR "\t" link_target
          }
          line = substr(line, link_start + link_len)
        }
      }
    ' "$md_file")

    [[ -z "$awk_output" ]] && continue

    while IFS=$'\t' read -r lineno link; do
      [[ -z "$link" ]] && continue
      # Resolve relative path based on document location
      local target_path
      if [[ "$link" == /* ]]; then
        target_path="${repo_root}${link}"
      else
        target_path="${dir}/${link}"
      fi
      if [[ ! -e "$target_path" ]]; then
        [[ "$first" == true ]] && first=false || results="${results},"
        results="${results}{\"doc\":\"$(_json_escape "$rel_doc")\",\"link\":\"$(_json_escape "$link")\",\"line\":${lineno}}"
      fi
    done <<< "$awk_output"
  done < <(find "$repo_root" -name '*.md' -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null)

  printf '[%s]' "$results"
}

# --- 3. check_undeclared_deps ---
# Extract file path mentions within backticks in the body text,
# and detect paths that exist but are not declared in depends-on
# JSON array: [{"doc":"path","mentioned":"path","line":N}]
check_undeclared_deps() {
  local repo_root="$1"
  local results=""
  local first=true

  while IFS= read -r md_file; do
    local deps
    deps=$(parse_depends_on "$md_file")
    local rel_doc
    rel_doc=$(_relpath "$md_file" "$repo_root")

    # Extract file-path-like strings from backticks in body text (avoiding subshell)
    local awk_output
    awk_output=$(awk '
      BEGIN { in_fm=0 }
      NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
      in_fm && /^---[[:space:]]*$/ { in_fm=0; next }
      !in_fm {
        line = $0
        while (match(line, /`([^`]+)`/)) {
          tick_start = RSTART
          tick_len = RLENGTH
          content = substr(line, tick_start + 1, tick_len - 2)
          # File-path-like strings (starting with src/, lib/, config/, scripts/, docs/ etc. and having an extension)
          if (content ~ /^(src|lib|config|scripts|docs|test|tests|spec|app|pkg|internal|cmd)\/.*\.[a-zA-Z0-9]+$/) {
            print NR "\t" content
          }
          line = substr(line, tick_start + tick_len)
        }
      }
    ' "$md_file")

    [[ -z "$awk_output" ]] && continue

    while IFS=$'\t' read -r lineno mentioned; do
      [[ -z "$mentioned" ]] && continue

      # Check if the file actually exists
      [[ ! -e "${repo_root}/${mentioned}" ]] && continue

      # Check if already declared in depends-on (exact match or glob match)
      local declared=false
      if [[ -n "$deps" ]]; then
        while IFS= read -r dep; do
          [[ -z "$dep" ]] && continue
          if [[ "$dep" == "$mentioned" ]]; then
            declared=true
            break
          fi
          # If it's a glob pattern
          if [[ "$dep" == *'*'* ]] || [[ "$dep" == *'?'* ]]; then
            if match_glob "$dep" "$mentioned"; then
              declared=true
              break
            fi
          fi
        done <<< "$deps"
      fi

      if [[ "$declared" == false ]]; then
        [[ "$first" == true ]] && first=false || results="${results},"
        results="${results}{\"doc\":\"$(_json_escape "$rel_doc")\",\"mentioned\":\"$(_json_escape "$mentioned")\",\"line\":${lineno}}"
      fi
    done <<< "$awk_output"
  done < <(find "$repo_root" -name '*.md' -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null)

  printf '[%s]' "$results"
}

# --- 4. check_orphaned_docs ---
# Detect md files that are not linked from any other md and have no depends-on
# JSON array: ["path1","path2"]
check_orphaned_docs() {
  local repo_root="$1"

  # Collect all md files
  local all_docs=()
  while IFS= read -r md_file; do
    local rel
    rel=$(_relpath "$md_file" "$repo_root")
    all_docs+=("$rel")
  done < <(find "$repo_root" -name '*.md' -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null)

  # Record documents that have depends-on
  local docs_with_deps=()
  for doc in "${all_docs[@]}"; do
    local deps
    deps=$(parse_depends_on "${repo_root}/${doc}")
    if [[ -n "$deps" ]]; then
      docs_with_deps+=("$doc")
    fi
  done

  # Collect link targets from all md files
  local linked_docs=()
  for doc in "${all_docs[@]}"; do
    local links
    links=$(extract_md_links "${repo_root}/${doc}" "$repo_root" 2>/dev/null || true)
    if [[ -n "$links" ]]; then
      while IFS= read -r link; do
        [[ -z "$link" ]] && continue
        linked_docs+=("$link")
      done <<< "$links"
    fi
  done

  # orphaned = no depends-on AND not linked from anywhere
  local results=""
  local first=true
  for doc in "${all_docs[@]}"; do
    # Skip if it has depends-on
    local has_deps=false
    for d in "${docs_with_deps[@]+"${docs_with_deps[@]}"}"; do
      if [[ "$d" == "$doc" ]]; then
        has_deps=true
        break
      fi
    done
    [[ "$has_deps" == true ]] && continue

    # Skip if linked from other documents
    local is_linked=false
    for l in "${linked_docs[@]+"${linked_docs[@]}"}"; do
      if [[ "$l" == "$doc" ]]; then
        is_linked=true
        break
      fi
    done
    [[ "$is_linked" == true ]] && continue

    # orphaned
    [[ "$first" == true ]] && first=false || results="${results},"
    results="${results}\"$(_json_escape "$doc")\""
  done

  printf '[%s]' "$results"
}

# --- 5. check_stale_signals ---
# Compare document last-updated date with depends-on target last-updated date,
# and detect cases where the drift is threshold_days or more
# JSON array: [{"doc":"path","doc_updated":"YYYY-MM-DD","dep_updated":"YYYY-MM-DD","drift_days":N}]
check_stale_signals() {
  local repo_root="$1"
  local threshold_days="${2:-90}"
  local results=""
  local first=true

  # Check if git is available
  if ! git -C "$repo_root" rev-parse --git-dir >/dev/null 2>&1; then
    printf '[]'
    return 0
  fi

  while IFS= read -r md_file; do
    local deps
    deps=$(parse_depends_on "$md_file")
    [[ -z "$deps" ]] && continue

    local rel_doc
    rel_doc=$(_relpath "$md_file" "$repo_root")

    # Document last-updated date (git log)
    local doc_date
    doc_date=$(git -C "$repo_root" log -1 --format='%at' -- "$rel_doc" 2>/dev/null)
    [[ -z "$doc_date" ]] && continue

    while IFS= read -r dep; do
      [[ -z "$dep" ]] && continue
      # Skip glob patterns (only concrete files are targeted)
      [[ "$dep" == *'*'* ]] || [[ "$dep" == *'?'* ]] && continue
      [[ ! -e "${repo_root}/${dep}" ]] && continue

      local dep_date
      dep_date=$(git -C "$repo_root" log -1 --format='%at' -- "$dep" 2>/dev/null)
      [[ -z "$dep_date" ]] && continue

      # Calculate drift in days
      local drift_seconds drift_days_val
      if [[ "$dep_date" -gt "$doc_date" ]]; then
        drift_seconds=$((dep_date - doc_date))
      else
        continue  # Skip if dep is older than doc
      fi
      drift_days_val=$((drift_seconds / 86400))

      if [[ "$drift_days_val" -ge "$threshold_days" ]]; then
        # macOS-compatible date format
        local doc_date_str dep_date_str
        if date -r 0 >/dev/null 2>&1; then
          # macOS
          doc_date_str=$(date -r "$doc_date" '+%Y-%m-%d')
          dep_date_str=$(date -r "$dep_date" '+%Y-%m-%d')
        else
          # Linux
          doc_date_str=$(date -d "@$doc_date" '+%Y-%m-%d')
          dep_date_str=$(date -d "@$dep_date" '+%Y-%m-%d')
        fi
        [[ "$first" == true ]] && first=false || results="${results},"
        results="${results}{\"doc\":\"$(_json_escape "$rel_doc")\",\"doc_updated\":\"${doc_date_str}\",\"dep_updated\":\"${dep_date_str}\",\"drift_days\":${drift_days_val}}"
      fi
    done <<< "$deps"
  done < <(find "$repo_root" -name '*.md' -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null)

  printf '[%s]' "$results"
}

# If --source-only is specified, exit after function definitions only
if [[ "${1:-}" == "--source-only" ]]; then return 0 2>/dev/null || exit 0; fi

# --- Argument parsing ---
AUDIT_MODE="full"
AUDIT_RANGE=""
AUDIT_JSON=false
AUDIT_CHECK_UNDECLARED=false
AUDIT_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --full) AUDIT_MODE="full"; shift ;;
    --range) AUDIT_MODE="range"; AUDIT_RANGE="$2"; shift 2 ;;
    --check-undeclared) AUDIT_CHECK_UNDECLARED=true; shift ;;
    --json) AUDIT_JSON=true; shift ;;
    --root) AUDIT_ROOT="$2"; shift 2 ;;
    --source-only) exit 0 ;;
    *) echo "[doc-audit] Unknown option: $1" >&2; exit 2 ;;
  esac
done

# Determine repository root
if [[ -n "$AUDIT_ROOT" ]]; then
  REPO_ROOT="$AUDIT_ROOT"
else
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

# --- Main processing ---

# Collect target md files
target_docs=()
if [[ "$AUDIT_MODE" == "range" ]] && [[ -n "$AUDIT_RANGE" ]]; then
  while IFS= read -r f; do
    [[ "$f" == *.md ]] && target_docs+=("$f")
  done < <(git -C "$REPO_ROOT" diff --name-only "$AUDIT_RANGE" 2>/dev/null)
  # Even for range mode, scan all md files (full audit, not just affected md files)
fi

# Count total number of md files
total_docs=$(find "$REPO_ROOT" -name '*.md' -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null | wc -l | tr -d ' ')

# Execute checks
if [[ "$AUDIT_CHECK_UNDECLARED" == true ]]; then
  undeclared=$(check_undeclared_deps "$REPO_ROOT")
  if [[ "$AUDIT_JSON" == true ]]; then
    printf '{"undeclared_deps":%s,"meta":{"total_docs_scanned":%s,"scope":"%s","commit_range":%s}}' \
      "$undeclared" "$total_docs" "$AUDIT_MODE" \
      "$(if [[ -n "$AUDIT_RANGE" ]]; then printf '"%s"' "$AUDIT_RANGE"; else printf 'null'; fi)"
  else
    echo "$undeclared"
  fi
  # exit code
  if [[ "$undeclared" != "[]" ]]; then
    exit 1
  fi
  exit 0
fi

# --full (default): run all checks
broken=$(check_broken_deps "$REPO_ROOT")
dead=$(check_dead_links "$REPO_ROOT")
undeclared=$(check_undeclared_deps "$REPO_ROOT")
orphaned=$(check_orphaned_docs "$REPO_ROOT")
stale=$(check_stale_signals "$REPO_ROOT")

if [[ "$AUDIT_JSON" == true ]]; then
  printf '{"broken_deps":%s,"dead_links":%s,"undeclared_deps":%s,"orphaned_docs":%s,"stale_signals":%s,"meta":{"total_docs_scanned":%s,"scope":"%s","commit_range":%s}}' \
    "$broken" "$dead" "$undeclared" "$orphaned" "$stale" "$total_docs" "$AUDIT_MODE" \
    "$(if [[ -n "$AUDIT_RANGE" ]]; then printf '"%s"' "$AUDIT_RANGE"; else printf 'null'; fi)"
else
  echo "broken_deps: $broken"
  echo "dead_links: $dead"
  echo "undeclared_deps: $undeclared"
  echo "orphaned_docs: $orphaned"
  echo "stale_signals: $stale"
fi

# exit code: 1 if any issues found
has_issues=false
for arr in "$broken" "$dead" "$undeclared" "$orphaned" "$stale"; do
  if [[ "$arr" != "[]" ]]; then
    has_issues=true
    break
  fi
done

if [[ "$has_issues" == true ]]; then
  exit 1
fi
exit 0
