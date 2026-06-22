#!/usr/bin/env bats

# voice-out スクリプトを source して sanitize 関数を呼ぶ
load_voice_out() {
  # voice-out 自体は実行されると say を呼んでしまうので、
  # sanitize 関数だけ抽出して評価する
  eval "$(sed -n '/^sanitize()/,/^}/p' "${BATS_TEST_DIRNAME}/../bin/voice-out")"
}

setup() {
  load_voice_out
}

@test "code block を仕切り語に置換" {
  result=$(sanitize $'```sh\necho hi\n```')
  [ "$result" = "コードブロック省略。" ]
}

@test "table を仕切り語に置換" {
  result=$(sanitize $'| a | b |\n|---|---|\n| 1 | 2 |')
  [ "$result" = "表省略。" ]
}

@test "長 URL を リンク に置換" {
  result=$(sanitize "see https://github.com/example/repo/pull/12345 ok")
  [[ "$result" == *"リンク。"* ]]
}

@test "markdown 見出し記号を除去" {
  result=$(sanitize $'# Title\n## Subtitle')
  [[ "$result" != *"#"* ]]
}

@test "bold 記号を除去し中身は残す" {
  result=$(sanitize "**重要**な点")
  [ "$result" = "重要な点" ]
}

@test "空入力で空出力" {
  result=$(sanitize "")
  [ -z "$result" ]
}

@test "改行 3 連続以上を 2 連続に圧縮" {
  result=$(sanitize $'a\n\n\n\nb')
  [ "$result" = $'a\n\nb' ]
}
