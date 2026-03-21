#!/bin/bash
# Claude Code Statusline
# Layout: Model │ Ctx ████▒▒ 85% (170k) │ 5h 90% | 7d 50% │ repo ⎇ branch

set -o pipefail

input=$(cat)

# ── Config ────────────────────────────────────────────────
CACHE_FILE="/tmp/claude_usage_cache.json"
CACHE_TTL=300
KEYCHAIN_ACCOUNT="snakashima"

# ── ANSI (Bright variants for dark backgrounds) ──────────
RST=$'\e[0m'  BOLD=$'\e[1m'
WHT=$'\e[1;97m'  GRAY=$'\e[90m'
ACC=$'\e[38;5;210m'
SEP=" ${WHT}│${RST} "

# ── Parse input (single jq call) ─────────────────────────
eval "$(echo "$input" | jq -r '
  @sh "MODEL=\(.model.display_name // "")",
  @sh "DIR=\(.workspace.current_dir // "")",
  @sh "USED=\(.context_window.used_percentage // "")",
  @sh "REM=\(.context_window.remaining_percentage // "")",
  @sh "TOKENS_IN=\(.context_window.total_input_tokens // 0)",
  @sh "CTX_SIZE=\(.context_window.context_window_size // 200000)",
  @sh "MODE=\(.output_style.name // .agent.name // "")"
' 2>/dev/null)"

# ── Helpers ───────────────────────────────────────────────
is_int() { case "$1" in ''|*[!0-9]*) return 1;; esac; }

bar() {
  local pct="$1" w="${2:-12}" filled=$(( $1 * ${2:-12} / 100 ))
  local i=0 out=""
  while [ "$i" -lt "$w" ]; do
    if [ "$i" -lt "$filled" ]; then
      out+="${ACC}█"
    else
      out+="${GRAY}▒"
    fi
    i=$((i + 1))
  done
  printf '%s%s' "$out" "$RST"
}

# ── [1] Model ────────────────────────────────────────────
sec_model=""
if [ -n "$MODEL" ] && [ "$MODEL" != "null" ]; then
  short="${MODEL#Claude }"
  sec_model="${BOLD}${ACC}${short}${RST}"
  if [ -n "$MODE" ] && [ "$MODE" != "null" ] && [ "$MODE" != "default" ]; then
    sec_model+=" ${WHT}| ${MODE}${RST}"
  fi
fi

# ── [2] Context Window ───────────────────────────────────
sec_ctx=""
if [ -n "$USED" ] && [ "$USED" != "null" ]; then
  u="${USED%%.*}"
  r="${REM%%.*}"
  : "${r:=$((100 - u))}"
  if is_int "$u" && is_int "$r"; then
    left=$(( CTX_SIZE - TOKENS_IN ))
    if [ "$left" -ge 1000 ] 2>/dev/null; then
      suffix="$(( left / 1000 ))k"
    else
      suffix="$left"
    fi
    sec_ctx="${WHT}Ctx${RST} $(bar "$r" 12) ${ACC}${r}%${RST} ${ACC}(${suffix})${RST}"
  fi
fi

# ── [3] Usage Limits (cached API call) ───────────────────
sec_limits=""
now=$(date +%s)

_refresh_cache() {
  local creds token exp_ms exp_s
  creds=$(security find-generic-password -s "Claude Code-credentials" -a "$KEYCHAIN_ACCOUNT" -w 2>/dev/null) || return
  token=$(echo "$creds" | jq -r '.claudeAiOauth.accessToken // empty')
  exp_ms=$(echo "$creds" | jq -r '.claudeAiOauth.expiresAt // 0')
  exp_s=$(( exp_ms / 1000 ))
  [ -z "$token" ] || [ "$now" -gt "$exp_s" ] && return
  curl -s --max-time 3 "https://api.anthropic.com/api/oauth/usage" \
    -H "Authorization: Bearer $token" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "User-Agent: Claude Code" > "$CACHE_FILE" 2>/dev/null
}

cache_age=$(( now - $(stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0) ))
[ ! -f "$CACHE_FILE" ] || [ "$cache_age" -gt "$CACHE_TTL" ] && _refresh_cache

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
    parts+="${WHT}${label}${RST} ${ACC}${r}%${RST}"
  done
  sec_limits="$parts"
fi

# ── [4] Repo & Branch ────────────────────────────────────
sec_repo=""
if [ -n "$DIR" ] && git -C "$DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  repo_name=$(basename "$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null)")
  branch=$(git -C "$DIR" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
  [ -n "$repo_name" ] && sec_repo="${BOLD}${ACC}${repo_name}${RST}"
  [ -n "$branch" ] && sec_repo+=" ${WHT}|${RST} ${ACC}${branch}${RST}"
fi
[ -z "$sec_repo" ] && [ -n "$DIR" ] && \
  sec_repo="${BOLD}${ACC}${DIR/#$HOME/\~}${RST}"

# ── Assemble ──────────────────────────────────────────────
out=""
for s in "$sec_model" "$sec_ctx" "$sec_limits" "$sec_repo"; do
  [ -n "$s" ] && out="${out:+${out}${SEP}}${s}"
done
echo "$out"
