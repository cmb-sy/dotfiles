#!/bin/bash

CONFIG_DIR="$HOME/.config/claude-stats"

INPUT=$(cat)

# --- 追加: 最新 transcript_path を voice-out 用 state file に記録 ---
mkdir -p "$HOME/.cache" 2>/dev/null
printf '%s' "$INPUT" | /opt/homebrew/bin/jq -r '.transcript_path // empty' \
  > "$HOME/.cache/claude-tts.last-transcript" 2>/dev/null

# --- 既存: claude-stats collector ---
[ -f "$CONFIG_DIR/project-path" ] || exit 0
[ -f "$CONFIG_DIR/env" ] || exit 0

set -a
source "$CONFIG_DIR/env"
set +a

printf '%s' "$INPUT" | (cd "$(cat "$CONFIG_DIR/project-path")" && exec uv run python collector.py)
