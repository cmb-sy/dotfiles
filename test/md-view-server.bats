#!/usr/bin/env bats
# md-view が作った html をこのマシンだけに配る bin/md-view-server。実物を空きポートで立てて curl で叩く。

load "helpers/common"
load "helpers/md-view-server"

setup() {
  make_tmpdir
  export MD_VIEW_DIR="$TEST_TMPDIR/served"
  MD_VIEW_PORT="$(free_port)"
  export MD_VIEW_PORT
  BASE="http://127.0.0.1:$MD_VIEW_PORT"
  mkdir -p "$MD_VIEW_DIR/h"
  printf '<h1>ページ</h1>\n' > "$MD_VIEW_DIR/h/page.html"
  # Beside the served dir, not in it: what a request must never reach.
  printf '<h1>外</h1>\n' > "$TEST_TMPDIR/outside.html"
  start_server
}

teardown() {
  stop_server
  rm -rf "$TEST_TMPDIR"
}

# refused <status> <text>: run in the foreground, the server must exit with
# that status and one line naming the cause. The alarm ends a server that
# started anyway, so a failure here cannot hang the suite.
refused() {
  run perl -e 'alarm shift; exec @ARGV' 5 "$MD_VIEW_SERVER"
  [ "$status" -eq "$1" ] || { echo "status $status: $output"; return 1; }
  [ "${#lines[@]}" -eq 1 ] || { echo "not one line: $output"; return 1; }
  printf '%s\n' "$output" | grep -qF "$2" || { echo "no '$2' in: $output"; return 1; }
}

@test "配信フォルダの html を返す" {
  expect 200 "$BASE/h/page.html"
  req -o "$TEST_TMPDIR/got" "$BASE/h/page.html"
  cmp "$TEST_TMPDIR/got" "$MD_VIEW_DIR/h/page.html"
}

@test "Content-Type は text/html; charset=utf-8" {
  req -D - -o /dev/null "$BASE/h/page.html" | tr -d '\r' |
    grep -qixF 'Content-Type: text/html; charset=utf-8'
}

@test "HEAD はヘッダだけを返し本文を送らない" {
  # Raw, not curl -I: curl never reads a body after HEAD, so it cannot tell.
  raw="$(printf 'HEAD /h/page.html HTTP/1.0\r\nHost: 127.0.0.1:%s\r\n\r\n' "$MD_VIEW_PORT" |
    nc -w 5 127.0.0.1 "$MD_VIEW_PORT" | tr -d '\r')"
  printf '%s\n' "$raw" | head -n 1 | grep -qF ' 200 '
  size="$(wc -c < "$MD_VIEW_DIR/h/page.html" | tr -d ' ')"
  printf '%s\n' "$raw" | grep -qixF "Content-Length: $size"
  [ "$(printf '%s\n' "$raw" | grep -c 'ページ')" -eq 0 ]
}

@test "日本語と空白の名前はパーセントエンコードで届く" {
  printf '<h1>計画</h1>\n' > "$MD_VIEW_DIR/h/計画 1.html"
  expect 200 "$BASE/h/%E8%A8%88%E7%94%BB%201.html"
  req "$BASE/h/%E8%A8%88%E7%94%BB%201.html" | grep -qxF '<h1>計画</h1>'
}

@test "Host が localhost:<ポート> でも返す" {
  expect 200 -H "Host: localhost:$MD_VIEW_PORT" "$BASE/h/page.html"
}

@test "Host のポートが違えば 403" {
  expect 403 -H "Host: 127.0.0.1:1" "$BASE/h/page.html"
}

@test "Host の名前が違えば 403" {
  expect 403 -H "Host: example.com:$MD_VIEW_PORT" "$BASE/h/page.html"
}

@test "Host にポートが無ければ 403" {
  expect 403 -H "Host: 127.0.0.1" "$BASE/h/page.html"
}

@test "Host ヘッダが無ければ 403" {
  expect 403 -H "Host:" "$BASE/h/page.html"
}

@test "../ で配信フォルダの外へ出る要求は 404" {
  expect 404 --path-as-is "$BASE/../outside.html"
  expect 404 --path-as-is "$BASE/h/../../outside.html"
}

@test "配信フォルダと名前の頭が同じ隣のフォルダも 404" {
  mkdir "$TEST_TMPDIR/served2"
  printf '<h1>隣</h1>\n' > "$TEST_TMPDIR/served2/x.html"
  expect 404 --path-as-is "$BASE/../served2/x.html"
}

@test "パーセントエンコードした ../ も 404" {
  expect 404 --path-as-is "$BASE/%2e%2e/outside.html"
  expect 404 --path-as-is "$BASE/h/%2E%2E%2F%2E%2E%2Foutside.html"
  expect 404 --path-as-is "$BASE/..%2foutside.html"
}

@test "外のファイルを指す symlink は 404" {
  ln -s "$TEST_TMPDIR/outside.html" "$MD_VIEW_DIR/h/link.html"
  expect 404 "$BASE/h/link.html"
}

@test "外のフォルダを指す symlink の先も 404" {
  ln -s "$TEST_TMPDIR" "$MD_VIEW_DIR/out"
  expect 404 "$BASE/out/outside.html"
}

@test "html 以外のファイルは 404" {
  printf 'memo\n' > "$MD_VIEW_DIR/h/notes.txt"
  printf '# md\n' > "$MD_VIEW_DIR/h/page.md"
  expect 404 "$BASE/h/notes.txt"
  expect 404 "$BASE/h/page.md"
}

@test "html の名前でも解決した先が html 以外なら 404" {
  printf 'memo\n' > "$MD_VIEW_DIR/h/notes.txt"
  ln -s notes.txt "$MD_VIEW_DIR/h/alias.html"
  expect 404 "$BASE/h/alias.html"
}

@test "フォルダは 404 で、一覧を出さない" {
  expect 404 "$BASE/"
  expect 404 "$BASE/h"
  expect 404 "$BASE/h/"
  [ "$(req "$BASE/h/" | grep -c 'page.html')" -eq 0 ]
}

@test ".html で終わる名前のフォルダも 404" {
  mkdir "$MD_VIEW_DIR/h/dir.html"
  expect 404 "$BASE/h/dir.html"
}

@test "通常のファイルでないものは 404" {
  # A FIFO: opening it would wait for a writer, so a miss shows as a timeout.
  mkfifo "$MD_VIEW_DIR/h/pipe.html"
  expect 404 --max-time 3 "$BASE/h/pipe.html"
}

@test "無いファイルは 404" {
  expect 404 "$BASE/h/none.html"
}

@test "NUL を含む要求は 404" {
  expect 404 "$BASE/h/page.html%00"
  expect 404 "$BASE/h/pa%00ge.html"
}

@test "GET と HEAD 以外は 405" {
  expect 405 -X POST "$BASE/h/page.html"
  expect 405 -X DELETE "$BASE/h/page.html"
  expect 405 -X PURGE "$BASE/h/page.html"
}

@test "405 は使えるメソッドを Allow で示す" {
  req -D - -o /dev/null -X POST "$BASE/h/page.html" | tr -d '\r' |
    grep -qixF 'Allow: GET, HEAD'
}

@test "127.0.0.1 だけで待ち受ける" {
  # Every listening socket of the server, one "n<address>:<port>" line each.
  listening="$(lsof -nP -a -p "$SERVER_PID" -iTCP -sTCP:LISTEN -Fn 2> /dev/null | grep '^n')"
  [ "$listening" = "n127.0.0.1:$MD_VIEW_PORT" ]
}

@test "黙ったままの接続があっても他の要求に答える" {
  # A browser keeps spare connections open and sends nothing on them.
  exec 9<> "/dev/tcp/127.0.0.1/$MD_VIEW_PORT"
  expect 200 --max-time 3 "$BASE/h/page.html"
  exec 9>&-
}

@test "配信フォルダが無くても起動し、後からできたファイルを返す" {
  stop_server
  export MD_VIEW_DIR="$TEST_TMPDIR/later"
  start_server
  mkdir -p "$MD_VIEW_DIR/h"
  printf '<h1>後</h1>\n' > "$MD_VIEW_DIR/h/page.html"
  expect 200 "$BASE/h/page.html"
}

@test "配信フォルダが symlink でも返す" {
  stop_server
  ln -s "$TEST_TMPDIR/served" "$TEST_TMPDIR/alias"
  export MD_VIEW_DIR="$TEST_TMPDIR/alias"
  start_server
  expect 200 "$BASE/h/page.html"
}

@test "MD_VIEW_PORT が 1〜65535 の整数でなければ起動せず 2 で終わる" {
  stop_server
  for bad in abc 0 01 65536 "$MD_VIEW_PORT " -1 1.5; do
    MD_VIEW_PORT="$bad" refused 2 'MD_VIEW_PORT'
  done
}

@test "MD_VIEW_DIR が絶対パスでなければ起動せず 2 で終わる" {
  stop_server
  MD_VIEW_DIR="served" refused 2 'MD_VIEW_DIR'
}

@test "ポートが使われていれば起動せず 1 行で理由を出す" {
  refused 1 'md-view-server: '
}
