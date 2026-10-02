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
  if [ -n "$FAKE_PID" ]; then
    kill "$FAKE_PID" 2>/dev/null
    wait "$FAKE_PID" 2>/dev/null  # reap so bash prints no "Terminated"
  fi
  return 0
}

# start_fake '<responses json>' -- serve the responses, set JEV_ENDPOINT and REQ_LOG.
start_fake() {
  printf '%s' "$1" > "$BATS_TEST_TMPDIR/responses.json"
  REQ_LOG="$BATS_TEST_TMPDIR/requests.log"
  : > "$REQ_LOG"
  rm -f "$BATS_TEST_TMPDIR/port"
  python3 "$REPO_DIR/test/helpers/jev-fake-server.py" \
    "$BATS_TEST_TMPDIR/responses.json" "$REQ_LOG" "$BATS_TEST_TMPDIR/port" \
    2> "$BATS_TEST_TMPDIR/fake.err" &
  FAKE_PID=$!
  for _ in $(seq 50); do
    [ -s "$BATS_TEST_TMPDIR/port" ] && break
    kill -0 "$FAKE_PID" 2>/dev/null || break
    sleep 0.1
  done
  if [ ! -s "$BATS_TEST_TMPDIR/port" ]; then
    # Show why, or a CI-only failure leaves nothing to go on.
    {
      echo "fake server did not start ($(command -v python3): $(python3 --version 2>&1))"
      cat "$BATS_TEST_TMPDIR/fake.err"
    } >&2
    return 1
  fi
  export JEV_ENDPOINT="http://127.0.0.1:$(cat "$BATS_TEST_TMPDIR/port")/v1/systemone"
}

ok_body() {  # ok_body <top-criterion> -- a score answer whose max probability is that label
  jq -cn --arg top "$1" '{model:"jev-1.13",answers:{impact:{type:"score",score:3.1,legend:{},
    probabilities:(["無関係","名前が同じだけ","知っておくとよい","設定や使い方を見直す価値がある","すぐ対応が要る"]
      | map({key:., value:(if . == $top then 0.8 else 0.05 end)}) | from_entries),
    confidence:0.9}},usage:{input_tokens:40,output_tokens:0}}'
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

@test "401 でそれ以降は送らず、残りは unauthorized で終了ステータス 4" {
  start_fake '[[401, "{\"error\":\"invalid key\"}"]]'
  run bash -c "$(declare -f cand); { cand c1; cand c2; } | '$GS' rate 2>/dev/null"
  [ "$status" -eq 4 ]
  printf '%s\n' "$output" | jq -e 'select(.id=="c1") | .error=="unauthorized"'
  printf '%s\n' "$output" | jq -e 'select(.id=="c2") | .error=="unauthorized"'
  n=$(grep -c . "$REQ_LOG") || n=0
  [ "$n" -eq 1 ]
}

@test "429 の後に成功すれば再試行して点数を返す" {
  body=$(ok_body "すぐ対応が要る")
  start_fake "[[429, \"{}\"], [200, $(printf '%s' "$body" | jq -Rs .)]]"
  run bash -c "$(declare -f cand); cand c1 | '$GS' rate"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e 'select(.id=="c1") | .level==4'
  n=$(grep -c . "$REQ_LOG") || n=0
  [ "$n" -eq 2 ]
}

@test "529 が続けば 3 回再試行してその候補だけ error" {
  start_fake '[[529, "{}"]]'
  run bash -c "$(declare -f cand); cand c1 | '$GS' rate"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e 'select(.id=="c1") | .error=="http 529"'
  n=$(grep -c . "$REQ_LOG") || n=0
  [ "$n" -eq 4 ]
}

@test "422 はその候補だけ error にして次の候補を採点する" {
  body=$(ok_body "知っておくとよい")
  start_fake "[[422, \"{}\"], [200, $(printf '%s' "$body" | jq -Rs .)]]"
  run bash -c "$(declare -f cand); { cand c1; cand c2; } | '$GS' rate"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e 'select(.id=="c1") | .error=="http 422"'
  printf '%s\n' "$output" | jq -e 'select(.id=="c2") | .level==2'
}

@test "壊れた応答はその候補だけ error" {
  start_fake '[[200, "not json"]]'
  run bash -c "$(declare -f cand); cand c1 | '$GS' rate"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e 'select(.id=="c1") | .error | startswith("bad response")'
}

@test "応答が遅すぎればその候補だけ error" {
  export JEV_TIMEOUT=1
  start_fake '[[200, "{}", 3]]'
  run bash -c "$(declare -f cand); cand c1 | '$GS' rate"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e 'select(.id=="c1") | .error | startswith("network")'
}

@test "応答が途中で切れてもその候補だけ error にして次を採点する" {
  body=$(ok_body "無関係")
  js=$(printf '%s' "$body" | jq -Rs .)
  start_fake "[[200, $js, 0, true], [200, $js]]"
  run bash -c "$(declare -f cand); { cand c1; cand c2; } | '$GS' rate"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e 'select(.id=="c1") | .error | startswith("network")'
  printf '%s\n' "$output" | jq -e 'select(.id=="c2") | .level==0'
}

@test "全体の持ち時間を超えたら残りは送らず deadline" {
  export JEV_DEADLINE=1 JEV_TIMEOUT=5
  body=$(ok_body "無関係")
  start_fake "[[200, $(printf '%s' "$body" | jq -Rs .), 2]]"
  run bash -c "$(declare -f cand); { cand c1; cand c2; cand c3; } | '$GS' rate"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e 'select(.id=="c3") | .error=="deadline"'
  n=$(grep -c . "$REQ_LOG") || n=0
  [ "$n" -lt 3 ]
}

@test "network の失敗が 3 候補続いたら残りは送らず network down" {
  export JEV_TIMEOUT=1
  start_fake '[[200, "{}", 2]]'
  run bash -c "$(declare -f cand); { cand c1; cand c2; cand c3; cand c4; } | '$GS' rate"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e 'select(.id=="c3") | .error | startswith("network:")'
  printf '%s\n' "$output" | jq -e 'select(.id=="c4") | .error=="network down"'
  n=$(grep -c . "$REQ_LOG") || n=0
  [ "$n" -eq 3 ]
}

@test "https でない外部の送り先は拒否して終了ステータス 64" {
  export JEV_ENDPOINT="http://example.com/x"
  run bash -c "$(declare -f cand); cand c1 | '$GS' rate 2>&1"
  [ "$status" -eq 64 ]
  printf '%s' "$output" | grep -qF 'https'
  n=$(printf '%s\n' "$output" | grep -cF '"id"') || n=0
  [ "$n" -eq 0 ]
}

@test "数値の環境変数が不正なら終了ステータス 64" {
  export JEV_DEADLINE=abc
  run bash -c "$(declare -f cand); cand c1 | '$GS' rate 2>&1"
  [ "$status" -eq 64 ]
  printf '%s' "$output" | grep -qF 'JEV_DEADLINE'
}

# rate_body <probabilities-json> [score] [confidence] -- an answer with those fields
rate_body() {
  printf '{"model":"jev","answers":{"impact":{"type":"score","score":%s,"legend":{},"probabilities":%s,"confidence":%s}},"usage":{}}' \
    "${2:-1.0}" "$1" "${3:-0.5}"
}

@test "probabilities が 1 始まりの番号なら受け取ったキーを添えて error" {
  body=$(rate_body '{"1":0.1,"2":0.7,"3":0.1,"4":0.05,"5":0.05}')
  start_fake "[[200, $(printf '%s' "$body" | jq -Rs .)]]"
  run bash -c "$(declare -f cand); cand c1 | '$GS' rate"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e 'select(.id=="c1") | .error | startswith("bad response: unexpected probability keys")'
  printf '%s\n' "$output" | jq -e 'select(.id=="c1") | .error | contains("'"'5'"'")'
}

@test "確率が true なら error" {
  body=$(rate_body '{"0":true,"1":0.1,"2":0.1,"3":0.1,"4":0.1}')
  start_fake "[[200, $(printf '%s' "$body" | jq -Rs .)]]"
  run bash -c "$(declare -f cand); cand c1 | '$GS' rate"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e 'select(.id=="c1") | .error | startswith("bad response")'
}

@test "score が文字列なら error" {
  body=$(rate_body '{"0":0.6,"1":0.1,"2":0.1,"3":0.1,"4":0.1}' '"high"')
  start_fake "[[200, $(printf '%s' "$body" | jq -Rs .)]]"
  run bash -c "$(declare -f cand); cand c1 | '$GS' rate"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e 'select(.id=="c1") | .error | startswith("bad response")'
}

@test "score が NaN でも出力は正しい JSON で error" {
  body=$(rate_body '{"0":0.6,"1":0.1,"2":0.1,"3":0.1,"4":0.1}' 'NaN')
  start_fake "[[200, $(printf '%s' "$body" | jq -Rs .)]]"
  run bash -c "$(declare -f cand); cand c1 | '$GS' rate"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e 'select(.id=="c1") | .error | startswith("bad response")'
}

@test "confidence が null や範囲外なら error" {
  body=$(rate_body '{"0":0.6,"1":0.1,"2":0.1,"3":0.1,"4":0.1}' 1.0 null)
  body2=$(rate_body '{"0":0.6,"1":0.1,"2":0.1,"3":0.1,"4":0.1}' 1.0 1.5)
  start_fake "[[200, $(printf '%s' "$body" | jq -Rs .)], [200, $(printf '%s' "$body2" | jq -Rs .)]]"
  run bash -c "$(declare -f cand); { cand c1; cand c2; } | '$GS' rate"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e 'select(.id=="c1") | .error | startswith("bad response")'
  printf '%s\n' "$output" | jq -e 'select(.id=="c2") | .error | startswith("bad response")'
}

@test "log が 1 行 1 候補で追記する" {
  run bash -c "printf '%s\n' \
    '{\"id\":\"c1\",\"scope\":\"github\",\"key\":\"ollama/ollama\",\"title\":\"v0.33.3\",\"score\":3.1,\"level\":3,\"confidence\":0.9,\"picked\":true}' \
    '{\"id\":\"c2\",\"scope\":\"services\",\"key\":\"Obsidian\",\"title\":\"1.9\",\"error\":\"http 422\",\"picked\":false}' \
    | '$GS' log 2026-09-30"
  [ "$status" -eq 0 ]
  printf '2026-09-30\tgithub\tollama/ollama\tv0.33.3\t3.1\t3\t0.9\t1\n' > "$BATS_TEST_TMPDIR/want"
  printf '2026-09-30\tservices\tObsidian\t1.9\t\t\t\t0\n' >> "$BATS_TEST_TMPDIR/want"
  cmp "$GAIN_JEV_STATE" "$BATS_TEST_TMPDIR/want"
}

@test "log は値の中のタブと改行を空白に置き換える" {
  run bash -c "printf '%s\n' \
    '{\"id\":\"c1\",\"scope\":\"news\",\"key\":\"k\",\"title\":\"a\\tb\\nc\",\"score\":1,\"level\":0,\"confidence\":0.5,\"picked\":false}' \
    | '$GS' log 2026-09-30"
  [ "$status" -eq 0 ]
  n=$(awk -F'\t' '{print NF}' "$GAIN_JEV_STATE")
  [ "$n" -eq 8 ]
  grep -qF 'a b c' "$GAIN_JEV_STATE"
}

@test "log は日付が不正なら何も書かず終了ステータス 64" {
  run bash -c "printf '{}\n' | '$GS' log 2026-9-30"
  [ "$status" -eq 64 ]
  n=0; [ -f "$GAIN_JEV_STATE" ] && n=$(grep -c . "$GAIN_JEV_STATE")
  [ "$n" -eq 0 ]
}

@test "log は区切りの無い日付も拒否して理由を出す" {
  run bash -c "printf '{}\n' | '$GS' log 20260930 2>&1"
  [ "$status" -eq 64 ]
  printf '%s' "$output" | grep -qF 'date must be YYYY-MM-DD'
}

@test "log は JSON でない行を飛ばして残りを書く" {
  run bash -c "printf '%s\n' 'oops' \
    '{\"id\":\"c1\",\"scope\":\"github\",\"key\":\"k\",\"title\":\"t\",\"score\":1,\"level\":1,\"confidence\":0.5,\"picked\":false}' \
    | '$GS' log 2026-09-30 2>&1"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qF 'skipped'
  n=$(grep -c . "$GAIN_JEV_STATE")
  [ "$n" -eq 1 ]
}

@test "log は型の合わない行を飛ばして数え、前後の正しい行は書く" {
  run bash -c "printf '%s\n' \
    '{\"id\":\"c1\",\"scope\":\"github\",\"key\":\"k\",\"title\":\"t1\",\"score\":1,\"level\":1,\"confidence\":0.5,\"picked\":true}' \
    '{\"id\":\"c2\",\"scope\":\"github\",\"key\":\"k\",\"title\":\"t2\",\"score\":1,\"level\":1,\"confidence\":0.5,\"picked\":\"false\"}' \
    '{\"id\":\"c3\",\"scope\":\"github\",\"key\":\"k\",\"title\":\"t3\",\"score\":[1,2],\"level\":1,\"confidence\":0.5,\"picked\":false}' \
    '{\"id\":\"c4\",\"scope\":\"github\",\"key\":\"\",\"title\":\"t4\",\"picked\":false}' \
    '{\"id\":\"c5\",\"scope\":\"github\",\"key\":\"k\",\"title\":\"t5\",\"score\":null,\"error\":\"http 422\",\"picked\":false}' \
    | '$GS' log 2026-09-30 2>&1"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qF 'skipped 3'
  printf '2026-09-30\tgithub\tk\tt1\t1\t1\t0.5\t1\n' > "$BATS_TEST_TMPDIR/want"
  printf '2026-09-30\tgithub\tk\tt5\t\t\t\t0\n' >> "$BATS_TEST_TMPDIR/want"
  cmp "$GAIN_JEV_STATE" "$BATS_TEST_TMPDIR/want"
}
