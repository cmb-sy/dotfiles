#!/bin/bash
# ==============================================================================
# Claude Code Statusline
#
# Displays a color-coded status bar at the bottom of the Claude Code terminal.
#
# Layout:
#   Model │ Ctx ████▒▒ 85% (170k) │ 5h 79% | 7d 49% │ repo | branch
#
# Sections:
#   [1] Model   - Active model name and output mode (if non-default)
#   [2] Context - Context window usage with progress bar and remaining tokens
#   [3] Limits  - API usage limits (5-hour rolling + 7-day) via cached API call
#   [4] Repo    - Git repository name and current branch
#
# Dependencies: jq, curl, git, bc, security (macOS Keychain)
# ==============================================================================

set -o pipefail

input=$(cat)

# ==============================================================================
# Configuration
# ==============================================================================

CACHE_FILE="/tmp/claude_usage_cache.json"
CACHE_TTL=300                 # Refresh usage data every 5 minutes
KEYCHAIN_ACCOUNT="snakashima" # macOS Keychain account for OAuth credentials

# ==============================================================================
# ANSI color palette (256-color, optimized for dark backgrounds)
#
#   WHT      - Bright white for labels and separators
#   GRAY     - Muted gray for progress bar empty slots
#   C_MODEL  - Lavender for model name
#   C_CTX    - Mint green for context window metrics
#   C_LIMIT  - Peach for API usage limits
#   C_REPO   - Sky blue for repository name
#   C_BRANCH - Soft violet for branch name
# ==============================================================================

RST=$'\e[0m'
WHT=$'\e[1;38;5;255m'
GRAY=$'\e[38;5;242m'
C_MODEL=$'\e[1;38;5;183m'
C_CTX=$'\e[38;5;114m'
C_LIMIT=$'\e[38;5;216m'
C_REPO=$'\e[38;5;117m'
C_BRANCH=$'\e[38;5;147m'

SEP=" ${WHT}│${RST} "

# ==============================================================================
# Parse input JSON from Claude Code (single jq invocation for performance)
# ==============================================================================

eval "$(echo "$input" | jq -r '
  @sh "MODEL=\(.model.display_name // "")",
  @sh "DIR=\(.workspace.current_dir // "")",
  @sh "USED=\(.context_window.used_percentage // "")",
  @sh "REM=\(.context_window.remaining_percentage // "")",
  @sh "TOKENS_IN=\(.context_window.total_input_tokens // 0)",
  @sh "CTX_SIZE=\(.context_window.context_window_size // 200000)",
  @sh "MODE=\(.output_style.name // .agent.name // "")"
' 2>/dev/null)"

# ==============================================================================
# Helpers
# ==============================================================================

# Check if a value is a non-negative integer
is_int() { case "$1" in ''|*[!0-9]*) return 1;; esac; }

# Render a progress bar: filled blocks (█) in color, empty slots (▒) in gray
# Usage: bar <percent> <width> <color>
bar() {
  local pct="$1" w="${2:-12}" col="$3" filled=$(( $1 * ${2:-12} / 100 ))
  local i=0 out=""
  while [ "$i" -lt "$w" ]; do
    [ "$i" -lt "$filled" ] && out+="${col}█" || out+="${GRAY}▒"
    i=$((i + 1))
  done
  printf '%s%s' "$out" "$RST"
}

# Format token count as human-readable (e.g., 170000 -> "170k")
format_tokens() {
  local n="$1"
  if [ "$n" -ge 1000 ] 2>/dev/null; then
    printf '%dk' "$(( n / 1000 ))"
  else
    printf '%d' "$n"
  fi
}

# ==============================================================================
# [1] Model name and output mode
# ==============================================================================

sec_model=""
if [ -n "$MODEL" ] && [ "$MODEL" != "null" ]; then
  sec_model="${C_MODEL}${MODEL#Claude }${RST}"
  if [ -n "$MODE" ] && [ "$MODE" != "null" ] && [ "$MODE" != "default" ]; then
    sec_model+=" ${WHT}|${RST} ${C_MODEL}${MODE}${RST}"
  fi
fi

# ==============================================================================
# [2] Context window remaining percentage and token count
# ==============================================================================

sec_ctx=""
if [ -n "$USED" ] && [ "$USED" != "null" ]; then
  u="${USED%%.*}"
  r="${REM%%.*}"
  : "${r:=$((100 - u))}"
  if is_int "$u" && is_int "$r"; then
    left=$(format_tokens $(( CTX_SIZE - TOKENS_IN )))
    sec_ctx="${WHT}Ctx${RST} $(bar "$r" 12 "$C_CTX") ${C_CTX}${r}%${RST} ${C_CTX}(${left})${RST}"
  fi
fi

# ==============================================================================
# [3] API usage limits (5-hour rolling window + 7-day)
#
# Fetches from https://api.anthropic.com/api/oauth/usage using OAuth token
# stored in macOS Keychain. Results are cached to CACHE_FILE for CACHE_TTL
# seconds to avoid excessive API calls (the statusline runs on every message).
# ==============================================================================

sec_limits=""
now=$(date +%s)

# Fetch fresh usage data if the OAuth token is still valid
_refresh_cache() {
  local creds token exp_s
  creds=$(security find-generic-password -s "Claude Code-credentials" -a "$KEYCHAIN_ACCOUNT" -w 2>/dev/null) || return
  token=$(echo "$creds" | jq -r '.claudeAiOauth.accessToken // empty')
  exp_s=$(( $(echo "$creds" | jq -r '.claudeAiOauth.expiresAt // 0') / 1000 ))
  [ -z "$token" ] || [ "$now" -gt "$exp_s" ] && return
  curl -s --max-time 3 "https://api.anthropic.com/api/oauth/usage" \
    -H "Authorization: Bearer $token" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "User-Agent: Claude Code" > "$CACHE_FILE" 2>/dev/null
}

# Only call API when cache is stale or missing
cache_age=$(( now - $(stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0) ))
[ ! -f "$CACHE_FILE" ] || [ "$cache_age" -gt "$CACHE_TTL" ] && _refresh_cache

# Parse cached usage and build display string
if [ -f "$CACHE_FILE" ]; then
  eval "$(jq -r '
    @sh "U5=\(.five_hour.utilization // "")",
    @sh "U7=\(.seven_day.utilization // "")"
  ' "$CACHE_FILE" 2>/dev/null)"

  parts=""
  for label_val in "5h:$U5" "7d:$U7"; do
    label="${label_val%%:*}"
    util="${label_val#*:}"
    [ -z "$util" ] || [ "$util" = "null" ] && continue
    r=$(echo "100 - $util" | bc 2>/dev/null)
    r="${r%%.*}"
    [ -z "$r" ] && continue
    [ -n "$parts" ] && parts+=" ${WHT}|${RST} "
    parts+="${WHT}${label}${RST} ${C_LIMIT}${r}%${RST}"
  done
  sec_limits="$parts"
fi

# ==============================================================================
# [4] Git repository name and current branch
# ==============================================================================

sec_repo=""
if [ -n "$DIR" ] && git -C "$DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  repo_name=$(basename "$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null)")
  branch=$(git -C "$DIR" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
  [ -n "$repo_name" ] && sec_repo="${C_REPO}${repo_name}${RST}"
  [ -n "$branch" ]    && sec_repo+=" ${WHT}|${RST} ${C_BRANCH}${branch}${RST}"
fi
[ -z "$sec_repo" ] && [ -n "$DIR" ] && \
  sec_repo="${C_REPO}${DIR/#$HOME/\~}${RST}"

# ==============================================================================
# Assemble and output
# ==============================================================================

out=""
for s in "$sec_model" "$sec_ctx" "$sec_limits" "$sec_repo"; do
  [ -n "$s" ] && out="${out:+${out}${SEP}}${s}"
done
echo "$out"
