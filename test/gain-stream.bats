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
  run --separate-stderr "$GST" topics --since 2026-10-03T00:00:00Z "$Y"
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

@test "budget: 問い合わせ回数を数え、Qiita の上限を超える設定は非 0" {
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
  run "$GST" budget "$Y"
  [ "$status" -eq 1 ]
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
  run --separate-stderr "$GST" topics --since 2026-10-05T00:00:00Z "$Y"
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
