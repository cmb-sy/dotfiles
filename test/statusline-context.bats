#!/usr/bin/env bats
# Tests for the context-window section ([3]) of claude/statusline.sh: the
# remaining-token figure in parentheses after the percentage.
#
# total_input_tokens is a session total, so it can exceed the window size.
# The remaining figure must come from the current usage instead and never go
# below zero.

load "helpers/common"

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  unset CLAUDE_CONFIG_DIR
  mkdir -p "$HOME"
  SCRIPT="$REPO_DIR/claude/statusline.sh"
}

run_statusline() {  # $1 = context_window JSON object
  printf '{"model":{"display_name":"Claude"},"context_window":%s}' "$1" | "$SCRIPT"
}

@test "total_input_tokens が窓より大きくても負の値を表示しない" {
  run run_statusline '{"used_percentage":30,"remaining_percentage":70,"total_input_tokens":1700000,"context_window_size":200000}'
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | grep -cF '(-')" -eq 0 ]
  echo "$output" | grep -qF '(140k)'
}

@test "current_usage があればそこから残りを求める" {
  run run_statusline '{"used_percentage":50,"remaining_percentage":50,"total_input_tokens":900000,"context_window_size":200000,"current_usage":{"input_tokens":50000,"output_tokens":7000,"cache_creation_input_tokens":10000,"cache_read_input_tokens":40000}}'
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF '(100k)'
}

@test "current_usage が窓を超えても 0 に丸める" {
  run run_statusline '{"used_percentage":100,"remaining_percentage":0,"context_window_size":200000,"current_usage":{"input_tokens":250000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}'
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | grep -cF '(-')" -eq 0 ]
  echo "$output" | grep -qF '(0)'
}

@test "current_usage が null なら used_percentage から求める" {
  run run_statusline '{"used_percentage":25,"remaining_percentage":75,"context_window_size":1000000,"current_usage":null}'
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF '(750k)'
}
