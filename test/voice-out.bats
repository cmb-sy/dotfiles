#!/usr/bin/env bats
# test/voice-out.bats — sanitize_text from the lib, pane resolution from the
# script. voice-out only runs its main flow when executed, so sourcing it here
# defines the helpers without speaking.

load "helpers/common"

setup() {
  . "$REPO_DIR/bin/lib/voice.sh"
}

load_voice_out() {
  . "$REPO_DIR/bin/voice-out"
}

@test "replaces code block with placeholder" {
  result=$(printf '%s' $'```sh\necho hi\n```' | sanitize_text)
  [ "$result" = "コードブロック省略。" ]
}

@test "replaces table with placeholder" {
  result=$(printf '%s' $'| a | b |\n|---|---|\n| 1 | 2 |' | sanitize_text)
  [ "$result" = "表省略。" ]
}

@test "replaces long URL with link placeholder" {
  result=$(printf '%s' "see https://github.com/example/repo/pull/12345 ok" | sanitize_text)
  printf '%s' "$result" | grep -qF "リンク。"
}

@test "strips markdown heading symbols" {
  result=$(printf '%s' $'# Title\n## Subtitle' | sanitize_text)
  hits=$(printf '%s' "$result" | grep -cF '#') || hits=0
  [ "$hits" -eq 0 ]
}

@test "strips bold markers but keeps content" {
  result=$(printf '%s' "**重要**な点" | sanitize_text)
  [ "$result" = "重要な点" ]
}

@test "empty input produces empty output" {
  result=$(printf '%s' "" | sanitize_text)
  [ -z "$result" ]
}

@test "collapses 3+ consecutive newlines into 2" {
  result=$(printf '%s' $'a\n\n\n\nb' | sanitize_text)
  [ "$result" = $'a\n\nb' ]
}

# --- resolve_focused_pane_id / load_from_visible_pane (mocked herdr) ---

@test "resolve_focused_pane_id: single pane in the focused workspace" {
  load_voice_out
  herdr() {
    case "$1 $2" in
      "workspace list") printf '{"result":{"workspaces":[{"workspace_id":"w1","focused":false},{"workspace_id":"w2","focused":true}]}}' ;;
      "pane list")      printf '{"result":{"panes":[{"pane_id":"w1:p1","workspace_id":"w1","focused":true},{"pane_id":"w2:p1","workspace_id":"w2","focused":false}]}}' ;;
    esac
  }
  result=$(resolve_focused_pane_id)
  [ "$result" = "w2:p1" ]
}

@test "resolve_focused_pane_id: prefers the individually-focused pane in a multi-pane workspace" {
  load_voice_out
  herdr() {
    case "$1 $2" in
      "workspace list") printf '{"result":{"workspaces":[{"workspace_id":"w1","focused":true}]}}' ;;
      "pane list")      printf '{"result":{"panes":[{"pane_id":"w1:p1","workspace_id":"w1","focused":false},{"pane_id":"w1:p2","workspace_id":"w1","focused":true}]}}' ;;
    esac
  }
  result=$(resolve_focused_pane_id)
  [ "$result" = "w1:p2" ]
}

@test "resolve_focused_pane_id: falls back to first pane when none report focused" {
  load_voice_out
  herdr() {
    case "$1 $2" in
      "workspace list") printf '{"result":{"workspaces":[{"workspace_id":"w1","focused":true}]}}' ;;
      "pane list")      printf '{"result":{"panes":[{"pane_id":"w1:p1","workspace_id":"w1","focused":false},{"pane_id":"w1:p2","workspace_id":"w1","focused":false}]}}' ;;
    esac
  }
  result=$(resolve_focused_pane_id)
  [ "$result" = "w1:p1" ]
}

@test "resolve_focused_pane_id: fails when no workspace is focused" {
  load_voice_out
  herdr() {
    case "$1 $2" in
      "workspace list") printf '{"result":{"workspaces":[{"workspace_id":"w1","focused":false}]}}' ;;
      "pane list")      printf '{"result":{"panes":[{"pane_id":"w1:p1","workspace_id":"w1","focused":true}]}}' ;;
    esac
  }
  run resolve_focused_pane_id
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "resolve_focused_pane_id: fails when herdr is unavailable" {
  load_voice_out
  unset -f herdr 2>/dev/null
  # Shadow PATH lookup too, in case a real herdr binary is installed on this machine
  command() { [ "$1" = "-v" ] && [ "$2" = "herdr" ] && return 1; builtin command "$@"; }
  run resolve_focused_pane_id
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "load_from_visible_pane: populates TEXT from herdr pane read" {
  load_voice_out
  herdr() {
    case "$1 $2" in
      "workspace list") printf '{"result":{"workspaces":[{"workspace_id":"w1","focused":true}]}}' ;;
      "pane list")      printf '{"result":{"panes":[{"pane_id":"w1:p1","workspace_id":"w1","focused":true}]}}' ;;
      "pane read")      printf '画面に見えているテキスト' ;;
    esac
  }
  load_from_visible_pane
  [ "$TEXT" = "画面に見えているテキスト" ]
}

@test "load_from_visible_pane: returns failure when pane read is empty" {
  load_voice_out
  herdr() {
    case "$1 $2" in
      "workspace list") printf '{"result":{"workspaces":[{"workspace_id":"w1","focused":true}]}}' ;;
      "pane list")      printf '{"result":{"panes":[{"pane_id":"w1:p1","workspace_id":"w1","focused":true}]}}' ;;
      "pane read")      printf '' ;;
    esac
  }
  run load_from_visible_pane
  [ "$status" -eq 1 ]
}
