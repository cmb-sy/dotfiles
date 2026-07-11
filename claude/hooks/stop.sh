#!/bin/bash

CONFIG_DIR="$HOME/.config/claude-stats"

INPUT=$(cat)

# --- Record latest transcript_path to the voice-out state file ---
# Resolve jq via PATH first (a hardcoded absolute path fails silently on Intel Macs / other environments)
JQ="$(command -v jq || true)"
[ -x "$JQ" ] || JQ=/opt/homebrew/bin/jq
[ -x "$JQ" ] || JQ=/usr/local/bin/jq
if [ -x "$JQ" ]; then
  mkdir -p "$HOME/.cache" 2>/dev/null
  printf '%s' "$INPUT" | "$JQ" -r '.transcript_path // empty' \
    > "$HOME/.cache/claude-tts.last-transcript" 2>/dev/null
fi

# --- claude-stats collector ---
[ -f "$CONFIG_DIR/project-path" ] || exit 0
[ -f "$CONFIG_DIR/env" ] || exit 0

set -a
source "$CONFIG_DIR/env"
set +a

printf '%s' "$INPUT" | (cd "$(cat "$CONFIG_DIR/project-path")" && exec uv run python collector.py)
