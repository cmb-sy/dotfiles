#!/usr/bin/env bats
# 同じ working tree で動く他の Claude セッションの検出。
#
# 検出できないより誤検出のほうが害が大きい（毎回出る警告は読まれなくなる）。
# 「該当が無ければ 1 行も出さない」を、実装が動いていない場合と区別できる形で検査する。

load "helpers/common"

setup() {
  PEERS="$REPO_DIR/bin/session-peers"
  export HERDR_PANE_ID="wSELF:p1"

  # 自分のリポジトリと、無関係なリポジトリを作る
  MY_REPO="$BATS_TEST_TMPDIR/mine"
  OTHER_REPO="$BATS_TEST_TMPDIR/other"
  mkdir -p "$MY_REPO/sub" "$OTHER_REPO"
  git -C "$MY_REPO" init -q
  git -C "$OTHER_REPO" init -q
}

# herdr をスタブ化する。$1 = panes 配列の中身（JSON）
stub_herdr() {
  export HERDR_BIN="$BATS_TEST_TMPDIR/herdr"
  printf '{"result":{"panes":[%s]}}' "$1" > "$BATS_TEST_TMPDIR/panes.json"
  cat > "$HERDR_BIN" <<'STUB'
#!/bin/bash
case "$1 $2" in "pane list") cat "$BATS_TEST_TMPDIR/panes.json" ;; esac
STUB
  chmod +x "$HERDR_BIN"
}

pane() {  # $1 = pane_id, $2 = cwd, $3 = status, $4 = agent（省略時 claude）
  printf '{"pane_id":"%s","cwd":"%s","agent_status":"%s","agent":"%s"}' \
    "$1" "$2" "$3" "${4:-claude}"
}

lines() { printf '%s' "$output" | grep -c . || true; }

# macOS の env に -C は無い（GNU 拡張）。サブシェルで移動する。
run_in() {  # $1 = dir
  local d="$1"; shift
  run bash -c "cd '$d' && bash '$PEERS'"
}

@test "同じ working tree の他セッションを検出する" {
  stub_herdr "$(pane wSELF:p1 "$MY_REPO" working),$(pane wA:p2 "$MY_REPO" idle)"
  run_in "$MY_REPO"
  [ "$status" -eq 0 ]
  n=$(printf '%s' "$output" | grep -cF 'wA:p2') || n=0
  [ "$n" -eq 1 ]
}

@test "自分自身は挙げない" {
  stub_herdr "$(pane wSELF:p1 "$MY_REPO" working)"
  run_in "$MY_REPO"
  [ "$status" -eq 0 ]
  [ "$(lines)" -eq 0 ]
}

@test "サブディレクトリにいるペインも同じ working tree とみなす" {
  stub_herdr "$(pane wSELF:p1 "$MY_REPO" working),$(pane wB:p3 "$MY_REPO/sub" idle)"
  run_in "$MY_REPO"
  n=$(printf '%s' "$output" | grep -cF 'wB:p3') || n=0
  [ "$n" -eq 1 ]
}

@test "別リポジトリのペインは挙げない" {
  stub_herdr "$(pane wSELF:p1 "$MY_REPO" working),$(pane wC:p1 "$OTHER_REPO" working)"
  run_in "$MY_REPO"
  [ "$status" -eq 0 ]
  [ "$(lines)" -eq 0 ]
}

@test "Claude が動いていないペインは挙げない" {
  stub_herdr "$(pane wSELF:p1 "$MY_REPO" working),$(pane wD:p1 "$MY_REPO" unknown none)"
  run_in "$MY_REPO"
  [ "$status" -eq 0 ]
  [ "$(lines)" -eq 0 ]
}

@test "状態（working / idle）を添える" {
  stub_herdr "$(pane wSELF:p1 "$MY_REPO" working),$(pane wE:p9 "$MY_REPO" working)"
  run_in "$MY_REPO"
  n=$(printf '%s' "$output" | grep -cF 'working') || n=0
  [ "$n" -ge 1 ]
}

@test "herdr が無い環境では何も出さず正常終了する" {
  export HERDR_BIN="$BATS_TEST_TMPDIR/does-not-exist"
  run_in "$MY_REPO"
  [ "$status" -eq 0 ]
  [ "$(lines)" -eq 0 ]
}

@test "git リポジトリでなければ何も出さず正常終了する" {
  plain="$BATS_TEST_TMPDIR/plain"
  mkdir -p "$plain"
  stub_herdr "$(pane wF:p1 "$MY_REPO" working)"
  run_in "$plain"
  [ "$status" -eq 0 ]
  [ "$(lines)" -eq 0 ]
}

@test "session-start.sh が session-peers を呼んでいる" {
  n=$(grep -cF 'session-peers' "$REPO_DIR/claude/hooks/session-start.sh") || n=0
  [ "$n" -ge 1 ]
}

@test "session-start.sh は handover が無くても peer 検査に到達する" {
  # handover ディレクトリの有無で早期 exit する前に peer を見ること。
  # 呼び出し行が最初の `exit 0` より前にあるかで判定する。
  f="$REPO_DIR/claude/hooks/session-start.sh"
  peer_line=$(grep -n 'session-peers' "$f" | head -1 | cut -d: -f1)
  # git リポジトリでない場合の脱出は peer 検査より前にあってよい（そもそも
  # 比較対象の working tree が無い）。検査するのは handover の早期 exit との順序。
  handover_line=$(grep -n 'HANDOVER_BASE" \]\] || exit 0' "$f" | head -1 | cut -d: -f1)
  [ -n "$peer_line" ]
  [ -n "$handover_line" ]
  [ "$peer_line" -lt "$handover_line" ]
}
