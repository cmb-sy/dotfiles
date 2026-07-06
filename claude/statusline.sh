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
# macOS の /usr/bin/awk (one true awk) は length() がマルチバイト非対応で
# UTF-8 文字をバイト数のままカウントしてしまう (絵文字やNerd Font アイコンが
# 3〜4 倍に水増しされる)。wc -m は Unicode コードポイント単位で数えるため、
# LC_ALL を明示的に UTF-8 化した上で使う (呼び出し元の locale 未設定に依存しない)。
visible_len() {
  printf '%s' "$1" | sed -E 's/\x1B\[[0-9;]*[[:alpha:]]//g' | LC_ALL=en_US.UTF-8 wc -m | tr -d ' '
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
# [3] Rate limits (5-hour rolling window + 7-day)
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
RL_PRESENT=$(echo "$input" | jq -r 'if .rate_limits then "1" else "" end' 2>/dev/null)
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
  # Prefer worktree name (from Claude Code JSON) over raw branch when present
  if has_val "$WORKTREE"; then
    sec_repo+=" ${WHT}│${RST} ${C_BRANCH}$(printf '\xee\x82\xa0') ${WORKTREE}${RST}"
  elif [ -n "$branch" ]; then
    sec_repo+=" ${WHT}│${RST} ${C_BRANCH}$(printf '\xee\x82\xa0') ${branch}${RST}"
  fi
  # Uncommitted change count (staged + unstaged + untracked)
  dirty=$(git -C "$DIR" --no-optional-locks status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  if is_int "$dirty" && [ "$dirty" -gt 0 ]; then
    sec_repo+=" ${C_DIRTY}●${dirty}${RST}"
  fi
fi
[ -z "$sec_repo" ] && [ -n "$DIR" ] && \
  sec_repo="${C_REPO}$(printf '\xef\x81\xbc') ${DIR/#$HOME/\~}${RST}"

# ==============================================================================
# [5] Voice input mode (Handy / Typeless)
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
# Assemble sections with separator and output
# ==============================================================================

out=""
for s in "$sec_model" "$sec_ctx" "$sec_limits" "$sec_repo" "$sec_voice"; do
  [ -n "$s" ] && out="${out:+${out}${SEP}}${s}"
done

# ==============================================================================
# [6] Right-aligned clock
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
