#!/bin/sh
# Claude Code status line command
# Reads JSON from stdin and outputs a formatted status line

input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
model=$(echo "$input" | jq -r '.model.display_name // ""')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
vim_mode=$(echo "$input" | jq -r '.vim.mode // empty')
session_name=$(echo "$input" | jq -r '.session_name // empty')

# Shorten home directory to ~
home="$HOME"
short_cwd=$(echo "$cwd" | sed "s|^$home|~|")

# Git branch (skip optional lock to avoid blocking)
git_branch=""
if [ -n "$cwd" ] && [ -d "$cwd/.git" ] || git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
  git_branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
fi

# Build status line with ANSI colors (terminal will dim them)
# Colors: cyan for path, yellow for git, blue for model, green/red for context
line=""

# Vim mode indicator
if [ -n "$vim_mode" ]; then
  case "$vim_mode" in
    INSERT) printf '\033[32m[INSERT]\033[0m ' ;;
    NORMAL) printf '\033[33m[NORMAL]\033[0m ' ;;
    *)      printf '\033[37m[%s]\033[0m ' "$vim_mode" ;;
  esac
fi

# Session name if set
if [ -n "$session_name" ]; then
  printf '\033[35m%s\033[0m ' "$session_name"
fi

# Current directory
printf '\033[36m%s\033[0m' "$short_cwd"

# Git branch
if [ -n "$git_branch" ]; then
  printf ' \033[33m(%s)\033[0m' "$git_branch"
fi

# Model
if [ -n "$model" ]; then
  printf ' \033[34m[%s]\033[0m' "$model"
fi

# Context usage
if [ -n "$used_pct" ]; then
  # Round to integer
  pct=$(printf '%.0f' "$used_pct")
  if [ "$pct" -ge 80 ]; then
    printf ' \033[31mCtx:%s%%\033[0m' "$pct"
  elif [ "$pct" -ge 50 ]; then
    printf ' \033[33mCtx:%s%%\033[0m' "$pct"
  else
    printf ' \033[32mCtx:%s%%\033[0m' "$pct"
  fi
fi

printf '\n'
