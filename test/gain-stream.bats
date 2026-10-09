#!/usr/bin/env bats
# bin/gain-stream の挙動。ネットワークには出ない（GAIN_STREAM_FIXTURES）。
#
# 黙って間違ったものを返す出どころ（絞り込みを無視して全期間を返す等）を
# 失敗として扱えることを、ここで固定する。

load "helpers/common"
bats_require_minimum_version 1.5.0   # run --separate-stderr

setup() {
  GST="$REPO_DIR/bin/gain-stream"
  export GAIN_STREAM_FIXTURES="$REPO_DIR/test/fixtures/gain-stream"
  export GAIN_STREAM_NOW="2026-10-02T06:00:00Z"
  Y="$BATS_TEST_TMPDIR/sources.yaml"
}

yaml() { printf '%s\n' "$1" > "$Y"; }

@test "topics: HN の記事を 1 行 1 件の JSON で出す" {
  yaml 'topics:
  - name: AI
    hn: ["claude code"]'
  run --separate-stderr "$GST" topics --since 2026-10-01T00:00:00Z "$Y"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"source": "hn"'
  printf '%s\n' "$output" | grep -qF '"title": "Claude Code now reads AGENTS.md"'
  printf '%s\n' "$output" | grep -qF '"published": "2026-10-01T21:00:32Z"'
  printf '%s\n' "$output" | grep -qF '"topic": "AI"'
  # url の無い記事は HN の議論ページを指す
  printf '%s\n' "$output" | grep -qF '"url": "https://news.ycombinator.com/item?id=2"'
  printf '%s\n' "$stderr" | grep -qF '"ok": true'
}

@test "期間より古い記事は落とす（サーバーが絞った後の端の分）" {
  yaml 'topics:
  - name: AI
    hn: ["claude code"]'
  run --separate-stderr "$GST" topics --since 2026-10-01T12:00:00Z "$Y"
  [ "$status" -eq 0 ]
  n=$(printf '%s\n' "$output" | grep -c '"source": "hn"') || n=0
  [ "$n" -eq 1 ]
}

@test "サーバーで絞るはずの出どころが期間外を返したら失敗にする" {
  yaml 'topics:
  - name: AI
    hn: ["claude code"]'
  # 余裕（1 日）を超えて古い記事が混ざる = 絞り込みが効いていない
  GAIN_STREAM_NOW="2026-10-06T00:00:00Z" run --separate-stderr "$GST" topics --since 2026-10-03T00:00:00Z "$Y"
  [ "$status" -eq 1 ]
  printf '%s\n' "$stderr" | grep -qF 'window not applied'
}

@test "fixture が無い出どころは失敗、ほかは続ける（終了コード 2）" {
  yaml 'topics:
  - name: AI
    hn: ["claude code", "no such query"]'
  run --separate-stderr "$GST" topics --since 2026-10-01T00:00:00Z "$Y"
  [ "$status" -eq 2 ]
  printf '%s\n' "$stderr" | grep -qF '"ok": false'
  printf '%s\n' "$output" | grep -qF 'AGENTS.md'
}

@test "sources.yaml が無い・壊れているときは終了コード 1" {
  run "$GST" topics --since 2026-10-01T00:00:00Z "$BATS_TEST_TMPDIR/none.yaml"
  [ "$status" -eq 1 ]
  printf 'topics: [\n' > "$Y"
  run "$GST" topics --since 2026-10-01T00:00:00Z "$Y"
  [ "$status" -eq 1 ]
}

@test "--since が無い・日時でないときは使い方の誤り（64）" {
  yaml 'topics: []'
  run "$GST" topics "$Y"
  [ "$status" -eq 64 ]
  run "$GST" topics --since yesterday "$Y"
  [ "$status" -eq 64 ]
}

@test "--since はタイムゾーン（Z か ±HH:MM）が無ければ 64" {
  yaml 'topics: []'
  run "$GST" topics --since 2026-10-01T00:00:00 "$Y"
  [ "$status" -eq 64 ]
  run "$GST" topics --since 2026-10-01T09:00:00+09:00 "$Y"
  [ "$status" -eq 0 ]
}

@test "--since が今より後なら 64（GAIN_STREAM_NOW に従う）" {
  yaml 'topics: []'
  run "$GST" topics --since 2026-10-02T06:00:01Z "$Y"
  [ "$status" -eq 64 ]
  run "$GST" discover --since 2026-10-02T06:00:00Z "$Y"
  [ "$status" -eq 0 ]
}

@test "fixture の名前は query から決まる（日本語は sha1 の先頭 8 桁）" {
  run python3 -c "import hashlib;print(hashlib.sha1('音声入力'.encode()).hexdigest()[:8])"
  h="$output"
  yaml 'topics:
  - name: 声
    hn: ["音声入力"]'
  run --separate-stderr "$GST" topics --since 2026-10-01T00:00:00Z "$Y"
  printf '%s\n' "$stderr" | grep -qF "no fixture hn-$h"
}

@test "topics が空なら何も出さずに 0" {
  yaml 'topics: []'
  run --separate-stderr "$GST" topics --since 2026-10-01T00:00:00Z "$Y"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "budget: 問い合わせ回数を数え、Qiita の上限を超える設定は終了コード 3" {
  yaml 'topics:
  - name: AI
    hn: ["a", "b"]
    qiita: ["x"]'
  run "$GST" budget "$Y"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"qiita": 1'
  qs=$(python3 -c 'print(", ".join(f"\"q{i}\"" for i in range(51)))')
  yaml "topics:
  - name: AI
    qiita: [$qs]"
  run --separate-stderr "$GST" budget "$Y"
  [ "$status" -eq 3 ]
  printf '%s\n' "$stderr" | grep -qF 'gain-stream: budget over: qiita 51 > 50'
}

@test "budget: sources.yaml を読めないときは超過（3）と分けて終了コード 1" {
  printf 'topics: [\n' > "$Y"
  run --separate-stderr "$GST" budget "$Y"
  [ "$status" -eq 1 ]
  printf '%s\n' "$stderr" | grep -qF 'gain-stream: sources.yaml is not valid YAML'
  n=$(printf '%s\n' "$stderr" | grep -c 'budget over') || n=0
  [ "$n" -eq 0 ]
}

@test "形の崩れた応答はその取得だけ失敗にし、ほかは続ける（終了コード 2）" {
  yaml 'topics:
  - name: AI
    hn: ["bad shape", "claude code"]'
  run --separate-stderr "$GST" topics --since 2026-10-01T00:00:00Z "$Y"
  [ "$status" -eq 2 ]
  printf '%s\n' "$stderr" | grep -qF 'bad shape: TypeError'
  printf '%s\n' "$output" | grep -qF 'AGENTS.md'
  n=$(printf '%s\n' "$stderr" | grep -c 'Traceback') || n=0
  [ "$n" -eq 0 ]
}

@test "sources.yaml の形の誤りは終了コード 1（topics・budget とも）" {
  yaml 'topics:
  - name: AI
    hn: "claude code"'
  run --separate-stderr "$GST" topics --since 2026-10-01T00:00:00Z "$Y"
  [ "$status" -eq 1 ]
  printf '%s\n' "$stderr" | grep -qF 'gain-stream: sources.yaml:'
  [ -z "$output" ]
  run --separate-stderr "$GST" budget "$Y"
  [ "$status" -eq 1 ]
  printf '%s\n' "$stderr" | grep -qF 'gain-stream: sources.yaml:'
  yaml 'topics: [AI]'
  run --separate-stderr "$GST" topics --since 2026-10-01T00:00:00Z "$Y"
  [ "$status" -eq 1 ]
  printf '%s\n' "$stderr" | grep -qF 'gain-stream: sources.yaml:'
  run --separate-stderr "$GST" budget "$Y"
  [ "$status" -eq 1 ]
  printf '%s\n' "$stderr" | grep -qF 'gain-stream: sources.yaml:'
  yaml 'people:
  - blog: https://example.com/feed'
  run --separate-stderr "$GST" budget "$Y"
  [ "$status" -eq 1 ]
  printf '%s\n' "$stderr" | grep -qF 'gain-stream: sources.yaml:'
  yaml 'discover: [x]'
  run --separate-stderr "$GST" budget "$Y"
  [ "$status" -eq 1 ]
  printf '%s\n' "$stderr" | grep -qF 'gain-stream: sources.yaml:'
}

@test "topics: はてブ・Qiita・Zenn・lobste.rs・Bluesky を同じ形で出す" {
  yaml 'topics:
  - name: AI
    hatena: ["claude code"]
    lobsters: ["ai"]
    bluesky: ["ollama"]
  - name: キャリア
    section: career
    qiita: ["career"]
    zenn: ["career"]'
  run --separate-stderr "$GST" topics --since 2026-10-01T00:00:00Z "$Y"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"source": "hatena", "title": "オレのClaude Code作業環境"'
  printf '%s\n' "$output" | grep -qF '"score": 571'
  printf '%s\n' "$output" | grep -qF '"url": "https://qiita.com/u/items/1"'
  printf '%s\n' "$output" | grep -qF '"section": "career"'
  printf '%s\n' "$output" | grep -qF '"author": "sakutaro"'
  printf '%s\n' "$output" | grep -qF '"source": "lobsters"'
  printf '%s\n' "$output" | grep -qF '"url": "https://bsky.app/profile/llama.bsky.social/post/3mtk"'
  # 公開日が期間外の Zenn の記事は落とす（Zenn は取得後に切る）
  n=$(printf '%s\n' "$output" | grep -c '古い記事') || n=0
  [ "$n" -eq 0 ]
}

@test "はてブが期間外を返したら失敗（不正な絞り込みは黙って全期間になる）" {
  yaml 'topics:
  - name: AI
    hatena: ["claude code"]'
  GAIN_STREAM_NOW="2026-10-06T00:00:00Z" run --separate-stderr "$GST" topics --since 2026-10-05T00:00:00Z "$Y"
  [ "$status" -eq 1 ]
  printf '%s\n' "$stderr" | grep -qF 'window not applied'
}

@test "壊れた XML は失敗にする" {
  mkdir -p "$BATS_TEST_TMPDIR/fx"
  printf '<rss><channel><item>' > "$BATS_TEST_TMPDIR/fx/lobsters-ai"
  yaml 'topics:
  - name: AI
    lobsters: ["ai"]'
  GAIN_STREAM_FIXTURES="$BATS_TEST_TMPDIR/fx" run --separate-stderr "$GST" topics --since 2026-10-01T00:00:00Z "$Y"
  [ "$status" -eq 1 ]
  printf '%s\n' "$stderr" | grep -qF 'bad xml'
}

@test "people: ブログ・Bluesky・Mastodon を本人の発信として出す" {
  yaml 'people:
  - name: Simon Willison
    blog: https://simonwillison.net/atom/everything/
    bluesky: simonwillison.net
    mastodon: https://fedi.simonwillison.net/@simon.rss'
  run --separate-stderr "$GST" topics --since 2026-10-01T00:00:00Z "$Y"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"title": "Quoting Matthew Green"'
  printf '%s\n' "$output" | grep -qF '"title": "Own post about Claude"'
  # Mastodon には題が無いので本文の先頭を題にする
  printf '%s\n' "$output" | grep -qF '"title": "Big model release today"'
  printf '%s\n' "$output" | grep -qF '"section": "people"'
  printf '%s\n' "$output" | grep -qF '"author": "Simon Willison"'
  # リポストは本人の発信ではない
  n=$(printf '%s\n' "$output" | grep -c 'Someone else') || n=0
  [ "$n" -eq 0 ]
}

@test "people の blog・bluesky・mastodon は文字列でなければ終了コード 1" {
  yaml 'people:
  - name: Simon Willison
    bluesky: [x]'
  run --separate-stderr "$GST" topics --since 2026-10-01T00:00:00Z "$Y"
  [ "$status" -eq 1 ]
  printf '%s\n' "$stderr" | grep -qF 'gain-stream: sources.yaml: people[0].bluesky must be a string'
  [ -z "$output" ]
  run --separate-stderr "$GST" budget "$Y"
  [ "$status" -eq 1 ]
  printf '%s\n' "$stderr" | grep -qF 'gain-stream: sources.yaml: people[0].bluesky must be a string'
}

discover_yaml() {
  yaml 'discover:
  hn_front: {min_points: 200}
  show_hn: {min_points: 80}
  hatena_it: {min_bookmarks: 100}
  zenn_trend: {limit: 10}
  qiita_popular: {limit: 10}
  github_new: {min_stars: 300}
  github_surging: {min_stars: 2000}
  ollama_newest: {limit: 10}
  hf_trending: {filters: ["text-generation"], limit: 10}'
}

@test "discover: 話題の技術の入口をすべて同じ形で出す" {
  discover_yaml
  run --separate-stderr "$GST" discover --since 2026-10-01T00:00:00Z "$Y"
  [ "$status" -eq 0 ]
  for s in hn_front show_hn hatena_it zenn_trend qiita_popular github_new github_surging ollama hf; do
    printf '%s\n' "$output" | grep -qF "\"source\": \"$s\""
  done
  printf '%s\n' "$output" | grep -qF '"url": "https://zenn.dev/mazrean/articles/bd9b"'
  printf '%s\n' "$output" | grep -qF '"url": "https://ollama.com/library/tev1"'
  printf '%s\n' "$output" | grep -qF '"url": "https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf"'
}

@test "discover: 人気の入口は日付で切らず、点数の下限で切る" {
  discover_yaml
  run --separate-stderr "$GST" discover --since 2026-10-01T00:00:00Z "$Y"
  # 09-20 の記事でも今人気なら残る
  printf '%s\n' "$output" | grep -qF 'AI時代の勉強法(2026)'
  # ブックマーク 12 は下限 100 に届かない
  n=$(printf '%s\n' "$output" | grep -c '"title": "少ない"') || n=0
  [ "$n" -eq 0 ]
}

@test "discover: GitHub の新規は直近 14 日で固定、Ollama は期間で切る" {
  discover_yaml
  run --separate-stderr "$GST" discover --since 2026-10-01T00:00:00Z "$Y"
  printf '%s\n' "$output" | grep -qF 'yetone/magpie'
  n=$(printf '%s\n' "$output" | grep -c 'old/repo') || n=0
  [ "$n" -eq 0 ]
  printf '%s\n' "$output" | grep -qF '"title": "tev1'
  n=$(printf '%s\n' "$output" | grep -c 'deepseek-v4.1-flash') || n=0
  [ "$n" -eq 0 ]
}

@test "discover: github_surging は作成日が古くても活発で星が多ければ拾う" {
  discover_yaml
  run --separate-stderr "$GST" discover --since 2026-10-01T00:00:00Z "$Y"
  [ "$status" -eq 0 ]
  # 2025 年作成でも拾う（created で切らない。星の下限は GitHub への検索条件で効く）
  printf '%s\n' "$output" | grep -qF 'usestrix/strix'
  printf '%s\n' "$output" | grep -qF '"source": "github_surging"'
  printf '%s\n' "$output" | grep -qF '"published": "2025-08-05T21:28:30Z"'
}

@test "discover: Ollama は一覧の title にある絶対日時を読む（「yesterday」のように相対時刻が読めない行も落とさない）" {
  discover_yaml
  run --separate-stderr "$GST" discover --since 2026-10-01T00:00:00Z "$Y"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -F '"url": "https://ollama.com/library/mistral-large-4"' \
    | grep -qF '"published": "2026-10-01T13:00:00Z"'
  printf '%s\n' "$output" | grep -F '"url": "https://ollama.com/library/tev1"' \
    | grep -qF '"published": "2026-10-01T19:00:00Z"'
}

@test "discover: Ollama のページからモデルを読めなければ失敗（形が変わった）" {
  mkdir -p "$BATS_TEST_TMPDIR/fx"
  cp "$GAIN_STREAM_FIXTURES"/* "$BATS_TEST_TMPDIR/fx/"
  printf '<html><body>redesigned</body></html>' > "$BATS_TEST_TMPDIR/fx/ollama-newest"
  discover_yaml
  GAIN_STREAM_FIXTURES="$BATS_TEST_TMPDIR/fx" run --separate-stderr "$GST" discover --since 2026-10-01T00:00:00Z "$Y"
  [ "$status" -eq 2 ]
  printf '%s\n' "$stderr" | grep -qF 'no models parsed'
}

@test "discover の各項目は null か mapping、hf_trending.filters は文字列の list（違えば終了コード 1）" {
  yaml 'discover: {hn_front: 5}'
  run --separate-stderr "$GST" discover --since 2026-10-01T00:00:00Z "$Y"
  [ "$status" -eq 1 ]
  printf '%s\n' "$stderr" | grep -qF 'gain-stream: sources.yaml: discover.hn_front must be a mapping'
  [ -z "$output" ]
  yaml 'discover:
  hf_trending: {filters: text-generation}'
  run --separate-stderr "$GST" budget "$Y"
  [ "$status" -eq 1 ]
  printf '%s\n' "$stderr" | grep -qF 'gain-stream: sources.yaml: discover.hf_trending.filters must be a list of strings'
  yaml 'discover:
  hn_front:
  hf_trending:'
  run --separate-stderr "$GST" budget "$Y"
  [ "$status" -eq 0 ]
}

@test "知らないキーは黙って無視せず終了コード 1（typo で何も取れないのを防ぐ）" {
  yaml 'topics:
  - name: AI
    hatana: ["claude code"]'
  run --separate-stderr "$GST" topics --since 2026-10-01T00:00:00Z "$Y"
  [ "$status" -eq 1 ]
  printf '%s\n' "$stderr" | grep -qF 'gain-stream: sources.yaml:'
  printf '%s\n' "$stderr" | grep -qF 'hatana'
  [ -z "$output" ]
  yaml 'people:
  - name: Simon Willison
    blgo: https://simonwillison.net/atom/everything/'
  run --separate-stderr "$GST" budget "$Y"
  [ "$status" -eq 1 ]
  printf '%s\n' "$stderr" | grep -qF 'blgo'
  yaml 'discover:
  hn_frnot: {min_points: 200}'
  run --separate-stderr "$GST" discover --since 2026-10-01T00:00:00Z "$Y"
  [ "$status" -eq 1 ]
  printf '%s\n' "$stderr" | grep -qF 'gain-stream: sources.yaml:'
  printf '%s\n' "$stderr" | grep -qF 'hn_frnot'
  # 他の道具が持つ最上位のキーは見ない
  yaml 'peers: [x]
other_tool: {a: 1}
topics:
  - name: AI
    note: memo
    section: flow
    hn: ["claude code"]'
  run --separate-stderr "$GST" budget "$Y"
  [ "$status" -eq 0 ]
}

@test "topics の section は文字列でなければ終了コード 1" {
  yaml 'topics:
  - name: AI
    section: [career]'
  run --separate-stderr "$GST" budget "$Y"
  [ "$status" -eq 1 ]
  printf '%s\n' "$stderr" | grep -qF 'gain-stream: sources.yaml: topics[0].section must be a string'
}

@test "Atom の entry は updated が先にあっても published の日付で切る" {
  yaml 'people:
  - name: Updated First
    blog: https://example.com/atom.xml'
  run --separate-stderr "$GST" topics --since 2026-10-01T00:00:00Z "$Y"
  [ "$status" -eq 0 ]
  printf '%s\n' "$stderr" | grep -qF '"ok": true'
  n=$(printf '%s\n' "$output" | grep -c 'Old post edited later') || n=0
  [ "$n" -eq 0 ]
}

@test "http・https 以外の URL は取得しない（fixture があっても）" {
  yaml 'people:
  - name: Simon Willison
    blog: file:///etc/hosts'
  run --separate-stderr "$GST" topics --since 2026-10-01T00:00:00Z "$Y"
  [ "$status" -eq 1 ]
  printf '%s\n' "$stderr" | grep -qF 'unsupported url scheme'
  [ -z "$output" ]
}

@test "discover: Ollama の公開日時を 1 件も読めなければ失敗（相対時刻の書き方が変わった）" {
  mkdir -p "$BATS_TEST_TMPDIR/fx"
  cp "$GAIN_STREAM_FIXTURES"/* "$BATS_TEST_TMPDIR/fx/"
  sed -E -e 's/ title="[A-Z][a-z]{2} [0-9]{1,2}, [0-9]{4}[^"]*"//' \
    -e 's/11 hours ago/yesterday/' -e 's/3 weeks ago/last month/' \
    "$GAIN_STREAM_FIXTURES/ollama-newest" > "$BATS_TEST_TMPDIR/fx/ollama-newest"
  discover_yaml
  GAIN_STREAM_FIXTURES="$BATS_TEST_TMPDIR/fx" run --separate-stderr "$GST" discover --since 2026-10-01T00:00:00Z "$Y"
  [ "$status" -eq 2 ]
  printf '%s\n' "$stderr" | grep -qF 'no dates parsed'
}
