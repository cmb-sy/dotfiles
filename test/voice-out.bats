#!/usr/bin/env bats

load_voice_out() {
  # Extract and eval only the sanitize function; running voice-out itself would call say
  eval "$(sed -n '/^sanitize()/,/^}/p' "${BATS_TEST_DIRNAME}/../bin/voice-out")"
}

# Extract log() + resolve_focused_pane_id() + load_from_visible_pane() only.
# These call `herdr` (not say/afplay), so tests mock `herdr` as a shell function
# instead of running the live binary.
load_pane_resolver() {
  eval "$(sed -n '/^log()/,/^}/p' "${BATS_TEST_DIRNAME}/../bin/voice-out")"
  eval "$(sed -n '/^resolve_focused_pane_id()/,/^}/p' "${BATS_TEST_DIRNAME}/../bin/voice-out")"
  eval "$(sed -n '/^load_from_visible_pane()/,/^}/p' "${BATS_TEST_DIRNAME}/../bin/voice-out")"
}

setup() {
  load_voice_out
}

@test "replaces code block with placeholder" {
  result=$(sanitize $'```sh\necho hi\n```')
  [ "$result" = "コードブロック省略。" ]
}

@test "replaces table with placeholder" {
  result=$(sanitize $'| a | b |\n|---|---|\n| 1 | 2 |')
  [ "$result" = "表省略。" ]
}

@test "replaces long URL with link placeholder" {
  result=$(sanitize "see https://github.com/example/repo/pull/12345 ok")
  [[ "$result" == *"リンク。"* ]]
}

@test "strips markdown heading symbols" {
  result=$(sanitize $'# Title\n## Subtitle')
  [[ "$result" != *"#"* ]]
}

@test "strips bold markers but keeps content" {
  result=$(sanitize "**重要**な点")
  [ "$result" = "重要な点" ]
}

@test "empty input produces empty output" {
  result=$(sanitize "")
  [ -z "$result" ]
}

@test "collapses 3+ consecutive newlines into 2" {
  result=$(sanitize $'a\n\n\n\nb')
  [ "$result" = $'a\n\nb' ]
}

# --- resolve_focused_pane_id / load_from_visible_pane (mocked herdr) ---

@test "resolve_focused_pane_id: single pane in the focused workspace" {
  load_pane_resolver
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
  load_pane_resolver
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
  load_pane_resolver
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
  load_pane_resolver
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
  load_pane_resolver
  unset -f herdr 2>/dev/null
  # Shadow PATH lookup too, in case a real herdr binary is installed on this machine
  command() { [ "$1" = "-v" ] && [ "$2" = "herdr" ] && return 1; builtin command "$@"; }
  run resolve_focused_pane_id
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "load_from_visible_pane: populates TEXT from herdr pane read" {
  load_pane_resolver
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
  load_pane_resolver
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
