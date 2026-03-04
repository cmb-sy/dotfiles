#!/bin/bash

USAGE_CACHE="${TMPDIR:-/tmp}/claude-statusline-usage.json"
USAGE_CACHE_AGE=60

get_usage_json() {
  local creds token
  if [ -n "$(security find-generic-password -s 'Claude Code-credentials' -w 2>/dev/null)" ]; then
    creds=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
  elif [ -f "${HOME}/.claude/.credentials.json" ]; then
    creds=$(cat "${HOME}/.claude/.credentials.json" 2>/dev/null)
  fi
  [ -z "$creds" ] && return 1
  token=$(echo "$creds" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
  [ -z "$token" ] && return 1
  curl -s --max-time 5 "https://api.anthropic.com/api/oauth/usage" \
    -H "Authorization: Bearer $token" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "Content-Type: application/json" 2>/dev/null
}

if [ -f "$USAGE_CACHE" ]; then
  age=$(($(date +%s) - $(stat -f %m "$USAGE_CACHE" 2>/dev/null || stat -c %Y "$USAGE_CACHE" 2>/dev/null)))
  [ "$age" -gt "$USAGE_CACHE_AGE" ] 2>/dev/null && unset age
fi
if [ -z "${age:-}" ] || [ ! -f "$USAGE_CACHE" ]; then
  tmp=$(get_usage_json 2>/dev/null)
  if [ -n "$tmp" ] && echo "$tmp" | jq -e '.five_hour or .seven_day' >/dev/null 2>&1; then
    echo "$tmp" >"$USAGE_CACHE"
  fi
fi
usage_json=""
[ -f "$USAGE_CACHE" ] && usage_json=$(cat "$USAGE_CACHE" 2>/dev/null)

input=$(cat)
CURRENT_DIR=$(echo "$input" | jq -r '.workspace.current_dir // ""')
MODEL_NAME=$(echo "$input" | jq -r '.model.display_name // ""')
USED_PCT=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
REMAINING_PCT=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')
TOTAL_INPUT=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
CONTEXT_SIZE=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
MODE=$(echo "$input" | jq -r '.output_style.name // .agent.name // "default" | if . == null then "default" else . end')

# ANSI: R=reset, B=bold, D=dim | C=cyan, G=green, P=purple | sep=separator
R=$'\e[0m'
B=$'\e[1m'
D=$'\e[2m'
C=$'\e[36m'
G=$'\e[32m'
P=$'\e[35m'
sep=$' | '

# 使用率に応じた色 (0-100)
usage_col() {
  local u=${1:-0}
  if   [ "$u" -lt 50 ] 2>/dev/null; then echo $'\e[92m'
  elif [ "$u" -lt 80 ] 2>/dev/null; then echo $'\e[93m'
  else echo $'\e[91m'
  fi
}

short_reset() {
  local iso="$1"
  [ -z "$iso" ] && return
  local t="${iso:0:19}"
  date -j -f "%Y-%m-%dT%H:%M:%S" "$t" "+%a %H:%M" 2>/dev/null || \
  date -d "$t" "+%a %H:%M" 2>/dev/null || echo "${iso:0:16}"
}

usage_block() {
  local label="$1" util="$2" resets="$3"
  [ -z "$util" ] && return
  local col
  col=$(usage_col "${util%.*}")
  local reset_str
  reset_str=$(short_reset "$resets")
  echo -n "${sep}${label} ${col}${util}%${R}"
  [ -n "$reset_str" ] && echo -n " ${D}(${reset_str})${R}"
}

# Repo · branch
repo=""
if [ -n "$CURRENT_DIR" ] && git -C "$CURRENT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  name=$(basename "$(git -C "$CURRENT_DIR" rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null)
  branch=$(git -C "$CURRENT_DIR" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
  [ -n "$name" ] && repo="${sep}${B}${C}${name}${R}"
  [ -n "$branch" ] && repo="${repo}${sep}${G}${branch}${R}"
fi
[ -z "$repo" ] && repo="${sep}${B}${C}$(echo "${CURRENT_DIR/#$HOME/~}" | rev | cut -d'/' -f1-3 | rev)${R}"

# Ctx: コンテキスト窓の使用率と残りトークン
ctx=""
if [ -n "$USED_PCT" ] && [ "$USED_PCT" != "null" ] && [ "$USED_PCT" != "true" ] && [ "$USED_PCT" != "false" ]; then
  u=$(echo "$USED_PCT" | cut -d. -f1)
  rem=${REMAINING_PCT:-$((100 - u))}; rem=$(echo "$rem" | cut -d. -f1)
  is_num() { case "$1" in ''|*[!0-9]*) return 1;; *) return 0;; esac; }
  if [ -n "$u" ] && [ -n "$rem" ] && is_num "$u" && is_num "$rem"; then
    if   [ "$u" -lt 30 ]; then col=$'\e[92m'
    elif [ "$u" -lt 50 ]; then col=$'\e[93m'
    elif [ "$u" -lt 60 ]; then col=$'\e[91m'
    else col=$'\e[1;31m'; fi
    remaining_tokens=$((CONTEXT_SIZE - TOTAL_INPUT))
    if [ "$remaining_tokens" -ge 1000 ] 2>/dev/null; then
      left_k=$((remaining_tokens / 1000))
      ctx="${sep}${D}Ctx:${R} ${col}${rem}%${R} ${D}(${left_k}k left)${R}"
    else
      ctx="${sep}${D}Ctx:${R} ${col}${rem}%${R} ${D}(${remaining_tokens} left)${R}"
    fi
  fi
fi

# 5h / 7d を repo の後に表示（プラン使用制限）
plan_limits=""
if [ -n "$usage_json" ] && echo "$usage_json" | jq -e '.five_hour or .seven_day' >/dev/null 2>&1; then
  five_util=$(echo "$usage_json" | jq -r '.five_hour.utilization // empty' 2>/dev/null)
  five_reset=$(echo "$usage_json" | jq -r '.five_hour.resets_at // empty' 2>/dev/null)
  seven_util=$(echo "$usage_json" | jq -r '.seven_day.utilization // empty' 2>/dev/null)
  seven_reset=$(echo "$usage_json" | jq -r '.seven_day.resets_at // empty' 2>/dev/null)
  plan_limits="${plan_limits}$(usage_block "5h" "$five_util" "$five_reset")"
  plan_limits="${plan_limits}$(usage_block "7d" "$seven_util" "$seven_reset")"
  opus_util=$(echo "$usage_json" | jq -r '.seven_day_opus.utilization // empty' 2>/dev/null)
  opus_reset=$(echo "$usage_json" | jq -r '.seven_day_opus.resets_at // empty' 2>/dev/null)
  [ -n "$opus_util" ] && plan_limits="${plan_limits}$(usage_block "7d Opus" "$opus_util" "$opus_reset")"
  sonnet_util=$(echo "$usage_json" | jq -r '.seven_day_sonnet.utilization // empty' 2>/dev/null)
  sonnet_reset=$(echo "$usage_json" | jq -r '.seven_day_sonnet.resets_at // empty' 2>/dev/null)
  [ -n "$sonnet_util" ] && plan_limits="${plan_limits}$(usage_block "7d Sonnet" "$sonnet_util" "$sonnet_reset")"
  extra_enabled=$(echo "$usage_json" | jq -r '.extra_usage.is_enabled // false' 2>/dev/null)
  if [ "$extra_enabled" = "true" ]; then
    extra_util=$(echo "$usage_json" | jq -r '.extra_usage.utilization // empty' 2>/dev/null)
    extra_used=$(echo "$usage_json" | jq -r '.extra_usage.used_credits // empty' 2>/dev/null)
    extra_limit=$(echo "$usage_json" | jq -r '.extra_usage.monthly_limit // empty' 2>/dev/null)
    if [ -n "$extra_util" ]; then
      plan_limits="${plan_limits}${sep}Extra $(usage_col "${extra_util%.*}")${extra_util}%${R}"
      [ -n "$extra_used" ] && [ -n "$extra_limit" ] && plan_limits="${plan_limits} ${D}(${extra_used}/${extra_limit})${R}"
    fi
  fi
fi

# Model
model=""
[ -n "$MODEL_NAME" ] && [ "$MODEL_NAME" != "null" ] && model="${D}Model:${R} ${P}${MODEL_NAME}${R}"

mode_display=""
if [ -n "$MODE" ] && [ "$MODE" != "null" ] && [ "$MODE" != "true" ] && [ "$MODE" != "false" ]; then
  mode_display="${sep}${D}Mode:${R} ${P}${MODE}${R}"
fi

echo "${model}${ctx}${mode_display}${repo}${plan_limits}${R}"
