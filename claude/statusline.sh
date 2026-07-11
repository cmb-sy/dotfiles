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

# Convert UNIX epoch seconds to human-readable duration until reset
# Returns empty string if the reset time has already passed
fmt_reset() {
  local reset_s="$1"
  is_int "$reset_s" || return
  local diff=$(( reset_s - NOW ))
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
# Claude Code 自身が stdin JSON で .rate_limits を渡してくれるので、Keychain や
# OAuth API call を一切介さない。常に最新 & ネットワーク呼び出しゼロ & token
# 失効や rate limit (429) の影響を受けない。.resets_at は UNIX epoch seconds。
#
# .rate_limits 自体が存在する限り 5h / 7d の両セクションを常に描画する
# (個別の used_percentage や resets_at が欠けても "--%" で穴埋め)。
# Claude Code はリセット直後など特定状況で片方を省略するケースがあり、
# 「片方しか出ない」と紛らわしいので明示的に両方表示する設計とする。
#
# used_percentage は float で来るため jq 側で floor して整数化する
# (bash の is_int チェックが小数点で false を返してしまうのを回避)。
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
    eta=$(fmt_reset "$reset")
    [ -n "$eta" ] && parts+=" ${C_RESET_ETA}(${eta})${RST}"
  done
  sec_limits="$parts"
fi

# ==============================================================================
# [5] Git repository name, branch, and uncommitted-change badge — disabled by
# user request (not a TODO; keep commented rather than deleted for easy
# re-enable). $DIR / $WORKTREE parsed from the jq block above are, as a
# result, currently only consumed inside this disabled block.
# ==============================================================================

sec_repo=""
# if [ -n "$DIR" ] && git -C "$DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
#   repo_name=$(basename "$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null)")
#   branch=$(git -C "$DIR" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
#   if [ -n "$repo_name" ]; then
#     rel_path=$(git -C "$DIR" rev-parse --show-prefix 2>/dev/null)
#     rel_path="${rel_path%/}"
#     if [ -n "$rel_path" ]; then
#       sec_repo="${C_REPO}$(printf '\xef\x81\xbc') ../${repo_name}/${rel_path}${RST}"
#     else
#       sec_repo="${C_REPO}$(printf '\xef\x81\xbc') ../${repo_name}${RST}"
#     fi
#   fi
#   # Prefer worktree name (from Claude Code JSON) over raw branch when present
#   if has_val "$WORKTREE"; then
#     sec_repo+=" ${WHT}│${RST} ${C_BRANCH}$(printf '\xee\x82\xa0') ${WORKTREE}${RST}"
#   elif [ -n "$branch" ]; then
#     sec_repo+=" ${WHT}│${RST} ${C_BRANCH}$(printf '\xee\x82\xa0') ${branch}${RST}"
#   fi
#   # Uncommitted change count (staged + unstaged + untracked)
#   dirty=$(git -C "$DIR" --no-optional-locks status --porcelain 2>/dev/null | wc -l | tr -d ' ')
#   if is_int "$dirty" && [ "$dirty" -gt 0 ]; then
#     sec_repo+=" ${C_DIRTY}●${dirty}${RST}"
#   fi
# fi
# [ -z "$sec_repo" ] && [ -n "$DIR" ] && \
#   sec_repo="${C_REPO}$(printf '\xef\x81\xbc') ${DIR/#$HOME/\~}${RST}"

# ==============================================================================
# [6] Voice input mode (Handy / Typeless)
#
# Typeless が起動中なら "typeless" を優先表示 (bundle path で検出、Electron 系の
# binary 名揺れに耐える)。それ以外は Handy の settings_store.json から
# provider + selected_language を読み、voice-switch モードを ja / en / cloud に
# マップして表示する。設定ファイル不在/parse 失敗の場合はセクション非表示。
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
for s in "$sec_model" "$sec_account" "$sec_ctx" "$sec_limits" "$sec_repo" "$sec_voice" "$sec_time"; do
  [ -n "$s" ] && out="${out:+${out}${SEP}}${s}"
done
printf '%s\n' "$out"
