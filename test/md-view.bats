#!/usr/bin/env bats
# md を隣の html に描画し file URL を出す。pandoc は実物を使う。

load "helpers/common"

setup() {
  make_tmpdir
  CMD="$BATS_TEST_DIRNAME/../bin/md-view"
  printf '# 見出し\n\n本文\n' > "$TEST_TMPDIR/plan.md"
}

teardown() { rm -rf "$TEST_TMPDIR"; }

@test "md の隣に html を作り file URL を 1 行出す" {
  run "$CMD" "$TEST_TMPDIR/plan.md"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  echo "$output" | grep -qE '^file://.*\.html$'
  [ -f "$TEST_TMPDIR/plan.html" ]
  grep -qF '<h1' "$TEST_TMPDIR/plan.html"
}

@test "空白と日本語のパスはエンコードされる" {
  cp "$TEST_TMPDIR/plan.md" "$TEST_TMPDIR/計画 1.md"
  run "$CMD" "$TEST_TMPDIR/計画 1.md"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  echo "$output" | grep -qF '%20'
  [ "$(echo "$output" | grep -c ' ')" -eq 0 ]
  [ -f "$TEST_TMPDIR/計画 1.html" ]
}

@test "存在しない md は 1 で終わり html を作らない" {
  run "$CMD" "$TEST_TMPDIR/none.md"
  [ "$status" -eq 1 ]
  [ ! -e "$TEST_TMPDIR/none.html" ]
}

@test "md 以外は 2 で終わる" {
  printf 'x\n' > "$TEST_TMPDIR/a.txt"
  run "$CMD" "$TEST_TMPDIR/a.txt"
  [ "$status" -eq 2 ]
}

@test "引数なしは 2 で終わる" {
  run "$CMD"
  [ "$status" -eq 2 ]
}

@test "pandoc が無ければ 1 で終わる" {
  PANDOC_BIN=/nonexistent run "$CMD" "$TEST_TMPDIR/plan.md"
  [ "$status" -eq 1 ]
  [ ! -e "$TEST_TMPDIR/plan.html" ]
}

@test "2 回目も同じ URL を出す" {
  run "$CMD" "$TEST_TMPDIR/plan.md"
  first="$output"
  run "$CMD" "$TEST_TMPDIR/plan.md"
  [ "$status" -eq 0 ]
  [ "$output" = "$first" ]
}

@test "ページの題は最初の H1 で、ファイル名の題を本文に足さない" {
  run "$CMD" "$TEST_TMPDIR/plan.md"
  [ "$status" -eq 0 ]
  grep -qF '<title>見出し</title>' "$TEST_TMPDIR/plan.html"
  [ "$(grep -c 'plan.md' "$TEST_TMPDIR/plan.html")" -eq 0 ]
  [ "$(grep -c '<h1' "$TEST_TMPDIR/plan.html")" -eq 1 ]
}

@test "H1 が無ければファイル名を題にする" {
  printf '本文だけ\n' > "$TEST_TMPDIR/memo.md"
  run "$CMD" "$TEST_TMPDIR/memo.md"
  [ "$status" -eq 0 ]
  grep -qF '<title>memo</title>' "$TEST_TMPDIR/memo.html"
}

@test "見出しへの目次が付き、pandoc 既定の幅制限を持たない" {
  printf '# 題\n\n## 背景\n\n本文\n\n## 方針\n\n本文\n' > "$TEST_TMPDIR/plan.md"
  run "$CMD" "$TEST_TMPDIR/plan.md"
  [ "$status" -eq 0 ]
  grep -qF '<nav class="toc">' "$TEST_TMPDIR/plan.html"
  grep -qF 'href="#背景"' "$TEST_TMPDIR/plan.html"
  [ "$(grep -c 'max-width: 36em' "$TEST_TMPDIR/plan.html")" -eq 0 ]
}
