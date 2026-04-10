#!/bin/bash

set -o pipefail

# ==============================================================================
# Configuration
# ==============================================================================

CACHE_FILE="/tmp/claude_usage_cache.json"
CACHE_TTL=300                 # Refresh usage data every 5 minutes
KEYCHAIN_ACCOUNT="snakashima" # macOS Keychain account for OAuth credentials
USAGE_API="https://api.anthropic.com/api/oauth/usage"

# ==============================================================================
# ANSI color palette (256-color, optimized for dark backgrounds)
# ==============================================================================

RST=$'\e[0m'                  # Reset all attributes
WHT=$'\e[1;38;5;255m'         # Bright white  - labels, separators
GRAY=$'\e[38;5;242m'          # Muted gray    - progress bar empty slots
C_RESET_ETA=$'\e[38;5;249m'  # Light gray    - time until reset
C_MODEL=$'\e[1;38;5;183m'     # Lavender      - model name
C_CTX=$'\e[38;5;114m'         # Mint green    - context window metrics
C_LIMIT=$'\e[38;5;216m'       # Peach         - API usage limits
C_REPO=$'\e[38;5;117m'        # Sky blue      - repository name
C_BRANCH=$'\e[38;5;147m'      # Soft violet   - branch name

SEP=" ${WHT}│${RST} "

# ==============================================================================
# Helpers
# ==============================================================================

# Check if a value is a non-negative integer
is_int() { case "$1" in ''|*[!0-9]*) return 1;; esac; }

# Check if a value is non-empty and not "null"
has_val() { [ -n "$1" ] && [ "$1" != "null" ]; }

# Drop trailing context-window hint from model label, e.g. " (1M)" or " （1M）"
strip_model_suffix() {
  printf '%s' "$1" | sed -E 's/[[:space:]]*(\([^)]*\)|（[^）]*）)$//'
}

# Return visible length (ANSI escape sequences stripped)
visible_len() {
  printf '%s' "$1" | sed -E 's/\x1B\[[0-9;]*[[:alpha:]]//g' | awk '{print length}'
}

# Render a progress bar: filled blocks (█) in accent color, empty slots (▒) in gray
# Usage: bar <percent> <width> <color>
bar() {
  local w="${2:-12}" col="$3" filled=$(( $1 * ${2:-12} / 100 )) i=0 out=""
  while [ "$i" -lt "$w" ]; do
    [ "$i" -lt "$filled" ] && out+="${col}█" || out+="${GRAY}▒"
    i=$((i + 1))
  done
  printf '%s%s' "$out" "$RST"
}

# Format token count as human-readable (e.g., 170000 -> "170k")
fmt_tokens() {
  if [ "$1" -ge 1000 ] 2>/dev/null; then
    printf '%dk' "$(( $1 / 1000 ))"
  else
    printf '%d' "$1"
  fi
}

# Convert ISO8601 UTC timestamp to human-readable duration until reset
# Returns empty string if the reset time has already passed
fmt_reset() {
  local ts="$1"
  has_val "$ts" || return
  local reset_s diff
  local clean="${ts%%[.+Z]*}"   # strip fractional seconds, tz offset, and trailing Z
  reset_s=$(TZ=UTC date -jf "%Y-%m-%dT%H:%M:%S" "$clean" +%s 2>/dev/null) || return
  diff=$(( reset_s - NOW ))
  [ "$diff" -le 0 ] && return
  printf '%dh%dm' "$(( diff / 3600 ))" "$(( (diff % 3600) / 60 ))"
}

# ==============================================================================
# Parse input JSON from Claude Code (single jq invocation for performance)
# ==============================================================================

input=$(cat)
NOW=$(date +%s)

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
# [1] Model name and output mode
# ==============================================================================

sec_model=""
if has_val "$MODEL"; then
  sec_model="${C_MODEL}$(strip_model_suffix "${MODEL#Claude }")${RST}"
  if has_val "$MODE" && [ "$MODE" != "default" ]; then
    sec_model+=" ${WHT}|${RST} ${C_MODEL}${MODE}${RST}"
  fi
fi

# ==============================================================================
# [2] Context window remaining percentage and token count
# ==============================================================================

sec_ctx=""
if has_val "$USED"; then
  u="${USED%%.*}" r="${REM%%.*}"
  : "${r:=$((100 - u))}"
  if is_int "$u" && is_int "$r"; then
    left=$(fmt_tokens $(( CTX_SIZE - TOKENS_IN )))
    sec_ctx="${WHT}Ctx${RST} $(bar "$r" 12 "$C_CTX") ${C_CTX}${r}%${RST} ${C_CTX}(${left})${RST}"
  fi
fi

# ==============================================================================
# [3] API usage limits (5-hour rolling window + 7-day)
#
# Fetches usage from Anthropic OAuth API using credentials stored in macOS
# Keychain. Results are cached to avoid hitting the API on every message.
# ==============================================================================

sec_limits=""

# Fetch fresh usage data from API (only if OAuth token is still valid)
_refresh_cache() {
  local creds token exp_s
  creds=$(security find-generic-password -s "Claude Code-credentials" \
    -a "$KEYCHAIN_ACCOUNT" -w 2>/dev/null) || return
  eval "$(echo "$creds" | jq -r '
    @sh "token=\(.claudeAiOauth.accessToken // "")",
    @sh "exp_s=\((.claudeAiOauth.expiresAt // 0) / 1000 | floor)"
  ')"
  has_val "$token" && [ "$NOW" -le "$exp_s" ] || return
  curl -s --max-time 3 "$USAGE_API" \
    -H "Authorization: Bearer $token" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "User-Agent: Claude Code" > "$CACHE_FILE" 2>/dev/null
}

# Refresh when cache is missing, empty, or older than CACHE_TTL
cache_age=$(( NOW - $(stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0) ))
if [ ! -s "$CACHE_FILE" ] || [ "$cache_age" -gt "$CACHE_TTL" ]; then
  _refresh_cache
fi

# Build display string from cached data
if [ -s "$CACHE_FILE" ]; then
  eval "$(jq -r '
    @sh "U5=\(.five_hour.utilization // "")",
    @sh "R5=\(.five_hour.resets_at // "")",
    @sh "U7=\(.seven_day.utilization // "")",
    @sh "R7=\(.seven_day.resets_at // "")"
  ' "$CACHE_FILE" 2>/dev/null)"

  parts=""
  for entry in "5h|$U5|$R5" "7d|$U7|$R7"; do
    IFS='|' read -r label util reset <<< "$entry"
    has_val "$util" || continue
    r=$(echo "100 - $util" | bc 2>/dev/null); r="${r%%.*}"
    [ -z "$r" ] && continue
    [ -n "$parts" ] && parts+=" ${WHT}·${RST} "
    parts+="${WHT}${label}${RST} ${C_LIMIT}${r}%${RST}"
    eta=$(fmt_reset "$reset")
    [ -n "$eta" ] && parts+=" ${C_RESET_ETA}(${eta})${RST}"
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
  if [ -n "$repo_name" ]; then
    rel_path=$(git -C "$DIR" rev-parse --show-prefix 2>/dev/null)
    rel_path="${rel_path%/}"
    if [ -n "$rel_path" ]; then
      sec_repo="${C_REPO}$(printf '\xef\x81\xbc') ../${repo_name}/${rel_path}${RST}"
    else
      sec_repo="${C_REPO}$(printf '\xef\x81\xbc') ../${repo_name}${RST}"
    fi
  fi
  [ -n "$branch" ]    && sec_repo+=" ${WHT}│${RST} ${C_BRANCH}$(printf '\xee\x82\xa0') ${branch}${RST}"
fi
[ -z "$sec_repo" ] && [ -n "$DIR" ] && \
  sec_repo="${C_REPO}$(printf '\xef\x81\xbc') ${DIR/#$HOME/\~}${RST}"

# ==============================================================================
# Assemble sections with separator and output
# ==============================================================================

out=""
for s in "$sec_model" "$sec_ctx" "$sec_limits" "$sec_repo"; do
  [ -n "$s" ] && out="${out:+${out}${SEP}}${s}"
done

# ==============================================================================
# [5] Right-aligned clock
# ==============================================================================
sec_time="${WHT}🕐 $(date +%H:%M)${RST}"

cols="${COLUMNS:-}"
if ! is_int "$cols" || [ "$cols" -lt 20 ]; then
  cols=$(tput cols 2>/dev/null || echo 120)
fi

out_len=$(visible_len "$out")
time_len=$(visible_len "$sec_time")
gap=$(( cols - out_len - time_len ))

if [ "$gap" -gt 1 ]; then
  printf '%s%*s%s\n' "$out" "$gap" "" "$sec_time"
else
  # Narrow terminals: avoid collapsing by falling back to inline separator.
  echo "${out}${SEP}${sec_time}"
fi
