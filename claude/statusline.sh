#!/bin/bash

set -o pipefail

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
C_BRANCH=$'\e[38;5;147m'      # Soft violet   - branch / worktree name
C_DIRTY=$'\e[1;38;5;215m'     # Amber         - uncommitted changes indicator
C_EFFORT=$'\e[1;38;5;220m'    # Gold          - reasoning effort level
C_VOICE=$'\e[38;5;177m'       # Soft magenta  - Handy voice input mode
C_ACCOUNT=$'\e[38;5;209m'     # Coral         - active Claude account

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

# Convert UNIX epoch seconds to an absolute reset clock time.
# $2 is a strftime format. Returns empty if the reset time already passed.
# Tries BSD date (-r) first, then GNU date (-d @) for portability.
fmt_reset() {
  local reset_s="$1" fmt="$2"
  is_int "$reset_s" || return
  [ "$(( reset_s - NOW ))" -le 0 ] && return
  date -r "$reset_s" "+$fmt" 2>/dev/null || date -d "@$reset_s" "+$fmt" 2>/dev/null
}

# ==============================================================================
# Parse input JSON from Claude Code (single jq invocation for performance)
# ==============================================================================

input=$(cat)
NOW=$(date +%s)

eval "$(echo "$input" | jq -r '
  @sh "MODEL=\(.model.display_name // "")",
  @sh "RL_PRESENT=\(if .rate_limits then "1" else "" end)",
  @sh "DIR=\(.workspace.current_dir // "")",
  @sh "USED=\(.context_window.used_percentage // "")",
  @sh "REM=\(.context_window.remaining_percentage // "")",
  @sh "TOKENS_IN=\(.context_window.total_input_tokens // 0)",
  @sh "CTX_SIZE=\(.context_window.context_window_size // 200000)",
  @sh "MODE=\(.output_style.name // .agent.name // "")",
  @sh "EFFORT=\(.effort.level // "medium")",
  @sh "WORKTREE=\(.worktree.name // "")",
  @sh "U5_PCT=\((.rate_limits.five_hour.used_percentage | floor?) // "")",
  @sh "R5_TS=\(.rate_limits.five_hour.resets_at // "")",
  @sh "U7_PCT=\((.rate_limits.seven_day.used_percentage | floor?) // "")",
  @sh "R7_TS=\(.rate_limits.seven_day.resets_at // "")"
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
  # Reasoning effort level (⚡). Values: low / medium / high / xhigh / max.
  # Defaults to "medium" when the field is absent (older CLI or unsupported model).
  if has_val "$EFFORT"; then
    sec_model+=" ${C_EFFORT}⚡${EFFORT}${RST}"
  fi
fi

# ==============================================================================
# [2] Active Claude account (multi-account switching via CLAUDE_CONFIG_DIR;
# see claude-use-private / claude-use-work in .aliases.sh). Falls back to
# resolving the ~/.claude symlink target when CLAUDE_CONFIG_DIR isn't
# inherited (e.g. a fresh terminal that didn't go through clp/clw).
# ==============================================================================

sec_account=""
acct_dir="${CLAUDE_CONFIG_DIR:-}"
if [ -z "$acct_dir" ] && [ -L "$HOME/.claude" ]; then
  acct_dir=$(readlink "$HOME/.claude")
fi
# Only trust a resolved, existing directory — a stale/broken ~/.claude symlink
# would otherwise print whatever garbage basename it happens to point at.
if [ -n "$acct_dir" ] && [ -d "$acct_dir" ]; then
  acct_name=$(basename "$acct_dir")
  acct_name="${acct_name#.claude-}"
  acct_name="${acct_name#.claude}"
  # Empty after stripping (dir literally named ".claude" or ".claude-") means
  # "not a recognizable per-account dir" — intentionally hide the section
  # rather than show a blank label.
  if has_val "$acct_name"; then
    sec_account="${C_ACCOUNT}${acct_name}${RST}"
    # Append the token-consuming account's identity. Two sources, in order:
    #
    # 1. <dir>/oauth-token.account — label recorded by claude-save-token-*
    #    at token-save time. This is authoritative when <dir>/oauth-token
    #    exists, because setup-token's long-lived tokens carry only the
    #    user:inference scope (no user:profile): neither we nor Claude Code
    #    can resolve the owner from the token via API, and the .claude.json
    #    profile cache is NEVER refreshed by token-injected sessions — it
    #    keeps showing whichever account last did a full `/login` there.
    # 2. Fallback: .claude.json .oauthAccount (the `/login` account), which
    #    is what actually consumes tokens when no oauth-token file exists.
    #
    # Shown as local-part@org (e.g. "alice@ExampleOrg") — enough to catch a
    # private/work token mismatch at a glance. Zero network calls.
    acct_id=""
    if [ -r "${acct_dir}/oauth-token" ]; then
      # Token file exists → that token is what's being consumed. Its owner is
      # whatever label was recorded at save time; if none was, show an
      # explicit "?" rather than falling back to the `/login` cache, which
      # would confidently display the WRONG account (the login one, not the
      # token one).
      if [ -r "${acct_dir}/oauth-token.account" ]; then
        acct_id=$(head -c 64 "${acct_dir}/oauth-token.account")
        acct_id="${acct_id%%@*}"
      else
        acct_id="?"
      fi
    else
      eval "$(jq -r '.oauthAccount |
        @sh "AE=\(.emailAddress // "")",
        @sh "AO=\(.organizationName // "")"
      ' "${acct_dir}/.claude.json" 2>/dev/null)"
      acct_id="${AE%%@*}"
      has_val "$acct_id" && has_val "$AO" && acct_id="${acct_id}@${AO}"
    fi
    has_val "$acct_id" && sec_account+=" ${C_ACCOUNT}(${acct_id})${RST}"
  fi
fi

# ==============================================================================
# [3] Context window remaining percentage and token count
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
# [4] Rate limits (5-hour rolling window + 7-day)
#
# Claude Code passes .rate_limits in the stdin JSON, so no Keychain access or
# OAuth API calls are needed — always current, zero network, unaffected by
# token expiry or 429s. .resets_at is UNIX epoch seconds.
#
# While .rate_limits exists, always render BOTH 5h and 7d sections, filling
# missing used_percentage/resets_at with "--%". Claude Code sometimes omits
# one window (e.g. right after a reset), and showing only one is confusing.
#
# used_percentage arrives as a float, so jq floors it to an integer
# (bash's is_int check would reject a decimal point).
# ==============================================================================

sec_limits=""
if [ -n "$RL_PRESENT" ]; then
  parts=""
  for entry in "5h|$U5_PCT|$R5_TS" "7d|$U7_PCT|$R7_TS"; do
    IFS='|' read -r label used reset <<< "$entry"
    [ -n "$parts" ] && parts+=" ${WHT}·${RST} "
    if is_int "$used"; then
      r=$(( 100 - used ))
      parts+="${WHT}${label}${RST} ${C_LIMIT}${r}%${RST}"
    else
      parts+="${WHT}${label}${RST} ${C_LIMIT}--%${RST}"
    fi
    # 5h resets within a day → clock time only; 7d can be days out → add date.
    if [ "$label" = "7d" ]; then
      eta=$(fmt_reset "$reset" '%m/%d %H:%M')
    else
      eta=$(fmt_reset "$reset" '%H:%M')
    fi
    [ -n "$eta" ] && parts+=" ${C_RESET_ETA}(${eta})${RST}"
  done
  sec_limits="$parts"
fi

# ==============================================================================
# [5] Current directory + uncommitted-change badge — rendered on its own
# second line (below the clock) rather than joined into the main line.
# Repo name / branch are intentionally NOT shown here (prior user request
# to keep this line to just directory + dirty count); $WORKTREE is unused.
# ==============================================================================

sec_dir=""
if has_val "$DIR"; then
  sec_dir="${C_REPO}$(printf '\xef\x81\xbc') ${DIR/#$HOME/\~}${RST}"
  if git -C "$DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # Uncommitted change count (staged + unstaged + untracked)
    dirty=$(git -C "$DIR" --no-optional-locks status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    if is_int "$dirty" && [ "$dirty" -gt 0 ]; then
      sec_dir+=" ${C_DIRTY}●${dirty}${RST}"
    fi
  fi
fi

# ==============================================================================
# [6] Voice input mode (Handy / Typeless)
#
# If Typeless is running, show "typeless" (detected via bundle path, robust
# to Electron binary-name drift). Otherwise read provider + selected_language
# from Handy's settings_store.json and map them to the voice-switch mode
# (ja / en / cloud). Hide the section if the file is missing or unparsable.
# ==============================================================================

sec_voice=""
TYPELESS_BIN_DIR="/Applications/Typeless.app/Contents/MacOS/"
HANDY_SETTINGS="$HOME/Library/Application Support/com.pais.handy/settings_store.json"

if /usr/bin/pgrep -f "$TYPELESS_BIN_DIR" >/dev/null 2>&1; then
  sec_voice="${WHT}voice${RST} ${C_VOICE}typeless${RST}"
elif [ -s "$HANDY_SETTINGS" ]; then
  eval "$(jq -r '
    (.settings // .) |
    @sh "V_PROV=\(.post_process_provider_id // "")",
    @sh "V_LANG=\(.selected_language // "")"
  ' "$HANDY_SETTINGS" 2>/dev/null)"
  if has_val "$V_PROV" && has_val "$V_LANG"; then
    case "$V_PROV" in
      cerebras) v_prov="cloud" ;;
      custom)   v_prov="local" ;;
      *)        v_prov="$V_PROV" ;;
    esac
    # Format: "voice local/ja" — provider first (the local-vs-cloud distinction
    # the user actually cares about), then language. Both share C_VOICE color.
    sec_voice="${WHT}voice${RST} ${C_VOICE}${v_prov}/${V_LANG}${RST}"
  fi
fi

# ==============================================================================
# [7] Assemble sections with separator and output. The clock is rendered
# inline as the final section rather than right-aligned — a prior right-pad-
# to-terminal-width approach undercounted the clock emoji's display width
# (wc -m counts it as 1 column, terminals render it as 2), so the line ran
# past the real width and Claude Code's UI clipped the clock off entirely.
# ==============================================================================

sec_time="${WHT}🕐 $(date +%H:%M)${RST}"

out=""
for s in "$sec_model" "$sec_account" "$sec_ctx" "$sec_limits" "$sec_voice" "$sec_time"; do
  [ -n "$s" ] && out="${out:+${out}${SEP}}${s}"
done
[ -n "$sec_dir" ] && out="${out}"$'\n'"${sec_dir}"
printf '%s\n' "$out"
