#!/usr/bin/env bats
# Jev に「自分の環境に効くか」を採点させる bin/gain-score の挙動。
#
# 本物の API は呼ばない。偽のサーバーを立て、JEV_ENDPOINT をそこへ向ける。

load "helpers/common"

setup() {
  GS="$REPO_DIR/bin/gain-score"
  export JEV_API_KEY="test-key"
  export JEV_BACKOFF_BASE=0
  export JEV_KEYCHAIN_SERVICE="gain-score-test-no-such-service"
  export GAIN_JEV_STATE="$BATS_TEST_TMPDIR/state/jev-scores.tsv"
  FAKE_PID=""
}

teardown() {
  [ -n "$FAKE_PID" ] && kill "$FAKE_PID" 2>/dev/null
  return 0
}

# start_fake '<responses json>' -- serve the responses, set JEV_ENDPOINT and REQ_LOG.
start_fake() {
  printf '%s' "$1" > "$BATS_TEST_TMPDIR/responses.json"
  REQ_LOG="$BATS_TEST_TMPDIR/requests.log"
  : > "$REQ_LOG"
  rm -f "$BATS_TEST_TMPDIR/port"
  python3 "$REPO_DIR/test/helpers/jev-fake-server.py" \
    "$BATS_TEST_TMPDIR/responses.json" "$REQ_LOG" "$BATS_TEST_TMPDIR/port" &
  FAKE_PID=$!
  for _ in $(seq 50); do
    [ -s "$BATS_TEST_TMPDIR/port" ] && break
    sleep 0.1
  done
  export JEV_ENDPOINT="http://127.0.0.1:$(cat "$BATS_TEST_TMPDIR/port")/v1/systemone"
}

ok_body() {  # ok_body <top-criterion> -- a score answer whose max probability is that label
  printf '{"model":"jev-1.13","answers":{"impact":{"type":"score","score":3.1,"legend":{},"probabilities":{"無関係":0.01,"名前が同じだけ":0.02,"知っておくとよい":0.07,"%s":0.8,"すぐ対応が要る":0.1},"confidence":0.9}},"usage":{"input_tokens":40,"output_tokens":0}}' "$1"
}

cand() {  # cand <id> -- one valid candidate line
  printf '{"id":"%s","scope":"github","key":"ollama/ollama","note":"Handy の後処理を動かすローカル実行環境","title":"v0.33.3","summary":"サンプラの既定値がモデル側の値を尊重するようになった"}\n' "$1"
}

@test "正常な応答を点数に変換する" {
  body=$(ok_body "設定や使い方を見直す価値がある")
  start_fake "[[200, $(printf '%s' "$body" | jq -Rs .)]]"
  run bash -c "$(declare -f cand); cand c1 | '$GS' rate"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e 'select(.id=="c1") | .level==3 and .score==3.1 and .confidence==0.9'
}

@test "リクエストが仕様の形をしている" {
  body=$(ok_body "無関係")
  start_fake "[[200, $(printf '%s' "$body" | jq -Rs .)]]"
  run bash -c "$(declare -f cand); cand c1 | '$GS' rate"
  [ "$status" -eq 0 ]
  jq -e '.auth == "Bearer test-key"' "$REQ_LOG"
  jq -e '.body | fromjson | .model == "jev-latest"
    and (.questions.impact.type == "score")
    and (.questions.impact.criteria | length == 5)
    and (.state | contains("Handy の後処理を動かすローカル実行環境"))
    and (.state | contains("v0.33.3"))' "$REQ_LOG"
}

@test "probabilities が段階の番号で返っても level を決められる" {
  body='{"model":"jev","answers":{"impact":{"type":"score","score":1.0,"legend":{},"probabilities":{"0":0.1,"1":0.7,"2":0.1,"3":0.05,"4":0.05},"confidence":0.6}},"usage":{}}'
  start_fake "[[200, $(printf '%s' "$body" | jq -Rs .)]]"
  run bash -c "$(declare -f cand); cand c1 | '$GS' rate"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e 'select(.id=="c1") | .level==1'
}

@test "キーが無ければ何も送らず終了ステータス 3" {
  unset JEV_API_KEY
  start_fake '[[200, "{}"]]'
  run bash -c "$(declare -f cand); cand c1 | '$GS' rate 2>&1"
  [ "$status" -eq 3 ]
  printf '%s' "$output" | grep -qF 'Jev 未設定'
  n=$(grep -c . "$REQ_LOG") || n=0
  [ "$n" -eq 0 ]
}

@test "必須キーが欠けた行と JSON でない行は error にして次へ進む" {
  body=$(ok_body "無関係")
  start_fake "[[200, $(printf '%s' "$body" | jq -Rs .)]]"
  run bash -c "{ printf '%s\n' '{\"id\":\"bad\",\"note\":\"n\"}' 'not json'; $(declare -f cand); cand c2; } | '$GS' rate"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e 'select(.id=="bad") | .error | contains("missing")'
  printf '%s\n' "$output" | jq -se 'map(select(.error? and (.error | contains("not JSON")))) | length == 1'
  printf '%s\n' "$output" | jq -e 'select(.id=="c2") | .level==0'
  n=$(grep -c . "$REQ_LOG") || n=0
  [ "$n" -eq 1 ]
}

@test "サブコマンドが無い・不明なら終了ステータス 64" {
  run "$GS"
  [ "$status" -eq 64 ]
  run "$GS" nope
  [ "$status" -eq 64 ]
}
