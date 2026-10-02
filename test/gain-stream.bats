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
