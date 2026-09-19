#!/usr/bin/env bats
# 印のついたセッションをサイドバーの上へ集める並べ替えの計画部分。
#
# 実際の移動は socket API（workspace.move / tab.move）で、CLI に口が無い。
# そこで計画だけを出す --plan を検査する。入力はスタブした herdr CLI が返す
# 固定 JSON で、socket には一切触れない。
#
# 行はワークスペース単位でまとまるため、印のあるタブを上に出すには、その
# タブを含むワークスペースごと上げるしかない。この「巻き添え」は仕様である。

load "helpers/common"

setup() {
  make_tmpdir
  STUB="$TEST_TMPDIR/bin"
  mkdir -p "$STUB"
  WS_JSON="$TEST_TMPDIR/ws.json"
  TAB_DIR="$TEST_TMPDIR/tabs"
  mkdir -p "$TAB_DIR"
  export WS_JSON TAB_DIR
  PATH="$STUB:$PATH"
  export HERDR_BIN="$STUB/herdr"

  cat >"$STUB/herdr" <<'STUB'
#!/bin/bash
case "$1 $2" in
  "workspace list") cat "$WS_JSON" ;;
  "tab list") cat "$TAB_DIR/$4.json" 2>/dev/null || echo '{"result":{"tabs":[]}}' ;;
  *) exit 1 ;;
esac
STUB
  chmod +x "$STUB/herdr"
}

teardown() { rm -rf "$TEST_TMPDIR"; }

# workspaces "id=label" ... （並び順そのまま）
# 区切りは = : tab_id は "w1P:tD" のように : を含むので使えない。
workspaces() {
  local out="" first=1 id label
  for spec in "$@"; do
    id="${spec%%=*}"; label="${spec#*=}"
    [ "$first" -eq 1 ] || out="$out,"
    first=0
    out="$out{\"workspace_id\":\"$id\",\"label\":\"$label\"}"
  done
  printf '{"result":{"workspaces":[%s]}}' "$out" >"$WS_JSON"
}

# tabs <workspace_id> "tab_id=label" ...
tabs() {
  local wid="$1"; shift
  local out="" first=1 id label
  for spec in "$@"; do
    id="${spec%%=*}"; label="${spec#*=}"
    [ "$first" -eq 1 ] || out="$out,"
    first=0
    out="$out{\"tab_id\":\"$id\",\"label\":\"$label\"}"
  done
  printf '{"result":{"tabs":[%s]}}' "$out" >"$TAB_DIR/$wid.json"
}

plan() { run bash "$REPO_DIR/bin/herdr-sort" --plan; }
plan_lines() {
  local n
  n=$(printf '%s' "$output" | grep -c .) || n=0
  printf '%s' "$n"
}

@test "印の無いワークスペースだけなら動かさない" {
  workspaces w1=alpha w2=beta
  tabs w1 t1=1
  tabs w2 t1=1
  plan
  [ "$status" -eq 0 ]
  [ "$(plan_lines)" -eq 0 ]
}

@test "印のついたワークスペースを先頭へ上げる" {
  workspaces w1=alpha w2=🤖beta w3=gamma
  tabs w1 t1=1
  tabs w2 t1=1
  tabs w3 t1=1
  plan
  printf '%s' "$output" | grep -qF "$(printf 'workspace.move\tworkspace_id\t0\tw2')"
  [ "$(plan_lines)" -eq 1 ]
}

@test "既に先頭なら動かさない" {
  workspaces w1=🤖alpha w2=beta
  tabs w1 t1=1
  tabs w2 t1=1
  plan
  [ "$(plan_lines)" -eq 0 ]
}

@test "印のついたタブを含むワークスペースも上げる（巻き添えは仕様）" {
  workspaces w1=alpha w2=beta
  tabs w1 w1:t1=1
  tabs w2 w2:ta=general w2:tb=📤stg
  plan
  printf '%s' "$output" | grep -qF "$(printf 'workspace.move\tworkspace_id\t0\tw2')"
  printf '%s' "$output" | grep -qF "$(printf 'tab.move\ttab_id\t0\tw2:tb')"
}

@test "ワークスペース内では印のついたタブを先頭へ" {
  workspaces w1=alpha
  tabs w1 w1:ta=one w1:tb=two w1:tc=🟢three
  plan
  printf '%s' "$output" | grep -qF "$(printf 'tab.move\ttab_id\t0\tw1:tc')"
}

@test "印つきが複数あっても元の相対順を保つ" {
  workspaces w1=plain w2=🤖second w3=other w4=📤fourth
  for w in w1 w2 w3 w4; do tabs $w t1=1; done
  plan
  # w2 が 0、w4 が 1。逆順にはならない。
  printf '%s' "$output" | grep -qF "$(printf 'workspace.move\tworkspace_id\t0\tw2')"
  printf '%s' "$output" | grep -qF "$(printf 'workspace.move\tworkspace_id\t1\tw4')"
}

@test "末尾の印つきも先頭まで上がる" {
  workspaces w1=plain w2=other w3=third w4=🤖last
  for w in w1 w2 w3 w4; do tabs $w t1=1; done
  plan
  printf '%s' "$output" | grep -qF "$(printf 'workspace.move\tworkspace_id\t0\tw4')"
}

@test "移動先に末尾の index を指定しない（herdr 側で丸められるため）" {
  # 左から順に置くので最後の 1 件は自動的に収まる。末尾を明示すると
  # insert_index が丸められ、狙った位置に入らない。
  workspaces w1=plain w2=other w3=third w4=🤖last
  for w in w1 w2 w3 w4; do tabs $w t1=1; done
  plan
  n=$(printf '%s' "$output" | grep -c "$(printf 'workspace_id\t3\t')") || n=0
  [ "$n" -eq 0 ]
}

@test "旧印 🔵 も印として扱う" {
  workspaces w1=alpha w2=🔵legacy
  tabs w1 t1=1
  tabs w2 t1=1
  plan
  printf '%s' "$output" | grep -qF "$(printf 'workspace.move\tworkspace_id\t0\tw2')"
}

@test "知らない引数は理由を示して失敗する" {
  workspaces w1=alpha
  tabs w1 t1=1
  run bash "$REPO_DIR/bin/herdr-sort" --bogus
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -qF 'unknown argument'
}
