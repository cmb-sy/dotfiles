#!/bin/bash

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

# Repo · branch
repo=""
if [ -n "$CURRENT_DIR" ] && git -C "$CURRENT_DIR" rev-parse --is-inside-work-tree 2>/dev/null; then
  name=$(basename "$(git -C "$CURRENT_DIR" rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null)
  branch=$(git -C "$CURRENT_DIR" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
  [ -n "$name" ] && repo="${sep}${B}${C}${name}${R}"
  [ -n "$branch" ] && repo="${repo}${sep}${G}${branch}${R}"
fi
[ -z "$repo" ] && repo="${sep}${B}${C}$(echo "${CURRENT_DIR/#$HOME/~}" | rev | cut -d'/' -f1-3 | rev)${R}"

# Context: 残り%・残りトークン
ctx=""
if [ -n "$USED_PCT" ] && [ "$USED_PCT" != "null" ]; then
  u=$(echo "$USED_PCT" | cut -d. -f1)
  rem=${REMAINING_PCT:-$((100 - u))}; rem=$(echo "$rem" | cut -d. -f1)
  if   [ "$u" -lt 30 ]; then col=$'\e[92m'
  elif [ "$u" -lt 50 ]; then col=$'\e[93m'
  elif [ "$u" -lt 60 ]; then col=$'\e[91m'
  else col=$'\e[1;31m'; fi
  remaining_tokens=$((CONTEXT_SIZE - TOTAL_INPUT))
  if [ "$remaining_tokens" -ge 1000 ] 2>/dev/null; then
    left_k=$((remaining_tokens / 1000))
    ctx="${sep}${D}Ctx :${R} ${col}${rem}%${R} ${D}(${left_k}k left)${R}"
  else
    ctx="${sep}${D}Ctx :${R} ${col}${rem}%${R} ${D}(${remaining_tokens} left)${R}"
  fi
fi

# Model
model=""
[ -n "$MODEL_NAME" ] && [ "$MODEL_NAME" != "null" ] && model="${D}Model :${R} ${P}${MODEL_NAME}${R}"

mode_display=""
if [ -n "$MODE" ] && [ "$MODE" != "null" ] && [ "$MODE" != "true" ] && [ "$MODE" != "false" ]; then
  mode_display="${sep}${D}Mode :${R} ${P}${MODE}${R}"
fi

echo "${model}${ctx}${mode_display}${repo}${sep}${R}"
