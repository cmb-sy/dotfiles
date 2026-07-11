#!/usr/bin/env bats

load_voice_out() {
  # Extract and eval only the sanitize function; running voice-out itself would call say
  eval "$(sed -n '/^sanitize()/,/^}/p' "${BATS_TEST_DIRNAME}/../bin/voice-out")"
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
