#!/bin/bash

CONFIG_DIR="$HOME/.config/claude-stats"

[ -f "$CONFIG_DIR/project-path" ] || exit 0
[ -f "$CONFIG_DIR/env" ] || exit 0

set -a
source "$CONFIG_DIR/env"
set +a

cd "$(cat "$CONFIG_DIR/project-path")" && exec uv run python collector.py
