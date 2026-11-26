#!/usr/bin/env bats
# md を隣の html に描画し、それを開く URL を 1 行出す。pandoc と md-view-server は実物を使う。

load "helpers/common"
load "helpers/md-view-server"
bats_require_minimum_version 1.5.0

setup() {
  make_tmpdir
  CMD="$BATS_TEST_DIRNAME/../bin/md-view"
  printf '# 見出し\n\n本文\n' > "$TEST_TMPDIR/plan.md"
  # Nothing listens on the port unless a test starts the server, so the URL
  # is file:// whatever runs on this machine's real port.
  export MD_VIEW_DIR="$TEST_TMPDIR/served"
  MD_VIEW_PORT="$(free_port)"
  export MD_VIEW_PORT
}

teardown() {
  stop_server
  rm -rf "$TEST_TMPDIR"
}

# The served copy's folder: sha256 of the md's real path, first 16 hex digits.
hash_of() { printf '%s' "$1" | shasum -a 256 | cut -c1-16; }

# A port that accepts connections and never answers. It closes by itself after
# 20 s, which is how long a probe with no time limit would then take.
start_silent_listener() {
  python3 -c 'import socket, sys, time
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", int(sys.argv[1])))
s.listen(8)
open(sys.argv[2], "w").close()
time.sleep(20)' "$MD_VIEW_PORT" "$TEST_TMPDIR/listening" 3>&- &
  SERVER_PID=$!
  local _
  for _ in $(seq 50); do
    [ -e "$TEST_TMPDIR/listening" ] && return 0
    sleep 0.1
  done
  echo "the silent listener did not start" >&2
  return 1
}

# still_listening: the port accepts a connection right now.
still_listening() { (exec 9<> "/dev/tcp/127.0.0.1/$MD_VIEW_PORT") 2> /dev/null; }

# days_ago <n>: that moment, in the form touch -t takes.
days_ago() { date -v-"$1"d +%Y%m%d%H%M.%S; }

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

@test "複製を 配信フォルダ/<md の絶対パスの sha256 先頭 16 桁>/<名前>.html に置く" {
  run "$CMD" "$TEST_TMPDIR/plan.md"
  [ "$status" -eq 0 ]
  copy="$MD_VIEW_DIR/$(hash_of "$TEST_TMPDIR/plan.md")/plan.html"
  [ -f "$copy" ]
  cmp "$copy" "$TEST_TMPDIR/plan.html"
}

@test "MD_VIEW_DIR が無ければ ~/.cache/md-view に複製を置く" {
  unset MD_VIEW_DIR
  export HOME="$TEST_TMPDIR/home"
  mkdir "$HOME"
  run "$CMD" "$TEST_TMPDIR/plan.md"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.cache/md-view/$(hash_of "$TEST_TMPDIR/plan.md")/plan.html" ]
}

@test "相対パスで渡しても symlink 越しに渡しても、同じ md の複製は 1 か所" {
  mkdir "$TEST_TMPDIR/real"
  cp "$TEST_TMPDIR/plan.md" "$TEST_TMPDIR/real/plan.md"
  ln -s real "$TEST_TMPDIR/link"
  cd "$TEST_TMPDIR/real"
  run "$CMD" plan.md
  [ "$status" -eq 0 ]
  run "$CMD" "$TEST_TMPDIR/link/plan.md"
  [ "$status" -eq 0 ]
  [ "$(ls "$MD_VIEW_DIR")" = "$(hash_of "$TEST_TMPDIR/real/plan.md")" ]
}

@test "サーバーが応答すれば http の URL を 1 行出し、そこからページが返る" {
  start_server
  run "$CMD" "$TEST_TMPDIR/plan.md"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [ "$output" = "http://127.0.0.1:$MD_VIEW_PORT/$(hash_of "$TEST_TMPDIR/plan.md")/plan.html" ]
  req -o "$TEST_TMPDIR/got" "$output"
  cmp "$TEST_TMPDIR/got" "$TEST_TMPDIR/plan.html"
}

@test "描き直しても同じ URL で、新しい内容が返る" {
  start_server
  run "$CMD" "$TEST_TMPDIR/plan.md"
  first="$output"
  printf '# 見出し\n\n書き直した本文\n' > "$TEST_TMPDIR/plan.md"
  run "$CMD" "$TEST_TMPDIR/plan.md"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE '^http://'
  [ "$output" = "$first" ]
  req "$output" | grep -qF '書き直した本文'
}

@test "日本語と空白の名前もエンコードした URL でサーバーから返る" {
  start_server
  cp "$TEST_TMPDIR/plan.md" "$TEST_TMPDIR/計画 1.md"
  run "$CMD" "$TEST_TMPDIR/計画 1.md"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  echo "$output" | grep -qE '^http://127\.0\.0\.1:[0-9]+/[0-9a-f]{16}/%E8%A8%88%E7%94%BB%201\.html$'
  req -o "$TEST_TMPDIR/got" "$output"
  cmp "$TEST_TMPDIR/got" "$TEST_TMPDIR/計画 1.html"
}

@test "つながっても答えないポートは待たずに見切り、file URL を出す" {
  start_silent_listener
  run "$CMD" "$TEST_TMPDIR/plan.md"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE '^file://.*\.html$'
  # md-view gave up by itself, not because the port closed under it.
  still_listening
}

@test "サーバーが別のフォルダを配っているときは file URL を出す" {
  MD_VIEW_DIR="$TEST_TMPDIR/elsewhere" start_server
  run "$CMD" "$TEST_TMPDIR/plan.md"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE '^file://.*\.html$'
}

@test "プロキシの環境変数があってもサーバーには直接たずねる" {
  start_server
  http_proxy="http://127.0.0.1:$(free_port)" no_proxy="" NO_PROXY="" run "$CMD" "$TEST_TMPDIR/plan.md"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE '^http://127\.0\.0\.1:'
}

@test "30 日より古い複製と、それで空になったフォルダを消す" {
  old="$MD_VIEW_DIR/0123456789abcdef"
  mixed="$MD_VIEW_DIR/fedcba9876543210"
  mkdir -p "$old" "$mixed"
  printf 'x\n' > "$old/a.html"
  printf 'x\n' > "$mixed/stale.html"
  printf 'x\n' > "$mixed/fresh.html"
  touch -t "$(days_ago 31)" "$old/a.html" "$mixed/stale.html"
  touch -t "$(days_ago 29)" "$mixed/fresh.html"
  run "$CMD" "$TEST_TMPDIR/plan.md"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [ ! -e "$old" ]
  [ ! -e "$mixed/stale.html" ]
  [ -f "$mixed/fresh.html" ]
}

@test "消すのは <16 桁の hex>/<名前>.html の形のものだけ" {
  hashed="$MD_VIEW_DIR/0123456789abcdef"
  mkdir -p "$hashed/sub" "$MD_VIEW_DIR/empty"
  kept="$MD_VIEW_DIR/top.html $MD_VIEW_DIR/docs/page.html $MD_VIEW_DIR/0123456789abcdef0/long.html
    $MD_VIEW_DIR/0123456789abcdeg/nothex.html $hashed/notes.txt $hashed/sub/deep.html"
  for f in $kept; do
    mkdir -p "$(dirname "$f")"
    printf 'x\n' > "$f"
    touch -t "$(days_ago 31)" "$f"
  done
  run "$CMD" "$TEST_TMPDIR/plan.md"
  [ "$status" -eq 0 ]
  for f in $kept; do
    [ -f "$f" ] || { echo "deleted: $f"; return 1; }
  done
  [ -d "$MD_VIEW_DIR/empty" ]
}

@test "掃除に失敗しても URL は出す" {
  # A folder find cannot enter makes the sweep fail.
  locked="$MD_VIEW_DIR/0123456789abcdef"
  mkdir -p "$locked"
  printf 'x\n' > "$locked/a.html"
  touch -t "$(days_ago 31)" "$locked/a.html"
  chmod 000 "$locked"
  run "$CMD" "$TEST_TMPDIR/plan.md"
  chmod 755 "$locked"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  echo "$output" | grep -qE '^file://.*/plan\.html$'
}

@test "MD_VIEW_PORT が 1〜65535 の整数でなければ 2 で終わり html を作らない" {
  for bad in abc 0 01 65536 99999999999999999999 "$MD_VIEW_PORT " -1 1.5; do
    MD_VIEW_PORT="$bad" run "$CMD" "$TEST_TMPDIR/plan.md"
    [ "$status" -eq 2 ] || { echo "MD_VIEW_PORT='$bad': status $status: $output"; return 1; }
    [ "${#lines[@]}" -eq 1 ] || { echo "MD_VIEW_PORT='$bad': not one line: $output"; return 1; }
    echo "$output" | grep -qF 'MD_VIEW_PORT' || { echo "MD_VIEW_PORT='$bad': $output"; return 1; }
  done
  [ ! -e "$TEST_TMPDIR/plan.html" ]
}

@test "MD_VIEW_DIR が絶対パスでなければ 2 で終わり html を作らない" {
  # A relative dir would land under the current one; keep that in the temp dir.
  cd "$TEST_TMPDIR"
  MD_VIEW_DIR="served" run "$CMD" "$TEST_TMPDIR/plan.md"
  [ "$status" -eq 2 ]
  echo "$output" | grep -qF 'MD_VIEW_DIR'
  [ ! -e "$TEST_TMPDIR/plan.html" ]
  [ ! -e "$TEST_TMPDIR/served" ]
}

@test "複製を置けなくても file URL を出して 0 で終わる" {
  # A file where the served dir should be: nothing can be created under it.
  printf 'x\n' > "$TEST_TMPDIR/blocked"
  MD_VIEW_DIR="$TEST_TMPDIR/blocked" run --separate-stderr "$CMD" "$TEST_TMPDIR/plan.md"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  echo "$output" | grep -qE '^file://.*/plan\.html$'
}

@test "既定のポートは md-view-server と同じ 8765" {
  # The default port cannot be bound here without meeting the real server,
  # so the two declarations are compared instead.
  grep -qxF 'port="${MD_VIEW_PORT:-8765}"' "$REPO_DIR/bin/md-view"
  grep -qxF '    port = os.environ.get("MD_VIEW_PORT") or "8765"' "$REPO_DIR/bin/md-view-server"
}
