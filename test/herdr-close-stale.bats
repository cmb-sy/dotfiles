#!/usr/bin/env bats
# 会話ログが N 日更新されていないワークスペースを閉じる。herdr のスタブと、mtime を合わせた偽の会話ログで検査する。

load "helpers/common"
bats_require_minimum_version 1.5.0

# 2026-03-01 12:00:00 UTC. Log ages are counted back from here.
NOW=1772366400
DAY=86400

setup() {
  make_tmpdir
  cat > "$TEST_TMPDIR/herdr" <<EOF
#!/bin/bash
case "\$1 \$2" in
  "workspace list") printf '%s' "\${FAKE_WS:-}"; exit "\${FAKE_WS_EXIT:-0}" ;;
  "agent list") printf '%s' "\${FAKE_AGENTS:-}"; exit "\${FAKE_AGENTS_EXIT:-0}" ;;
esac
printf "%s\\n" "\$*" >> "$TEST_TMPDIR/calls"
if [ "\$1 \$2" = "workspace close" ] && [ "\$3" = "\${FAKE_CLOSE_FAIL:-}" ]; then
  echo "herdr: cannot close \$3" >&2
  exit 1
fi
EOF
  chmod +x "$TEST_TMPDIR/herdr"
  export HERDR_BIN="$TEST_TMPDIR/herdr"
  export HERDR_CLOSE_STALE_ROOTS="$TEST_TMPDIR/acct1:$TEST_TMPDIR/acct2"
  export HERDR_CLOSE_STALE_NOW="$NOW"
  # Output dates are local time; pin the zone so they are fixed.
  export TZ=UTC
  CMD="$BATS_TEST_DIRNAME/../bin/herdr-close-stale"
}

teardown() { rm -rf "$TEST_TMPDIR"; }

# ws <id> <label> <focused> <pane_count>
ws() {
  printf '{"workspace_id":"%s","label":"%s","focused":%s,"agent_status":"idle","pane_count":%s,"tab_count":%s}' \
    "$1" "$2" "$3" "$4" "$4"
}

# ag <workspace_id> <agent_status> <session_id>
ag() {
  printf '{"pane_id":"%s:p%s","workspace_id":"%s","agent_status":"%s","focused":false,"agent_session":{"value":"%s"}}' \
    "$1" "$3" "$1" "$2" "$3"
}

# state <workspaces> <agents>: comma-joined objects from ws / ag.
state() {
  export FAKE_WS="{\"result\":{\"workspaces\":[$1]}}"
  export FAKE_AGENTS="{\"result\":{\"agents\":[$2]}}"
}

# log_at <account_dir> <session_id> <age_seconds>
log_at() {
  local f="$TEST_TMPDIR/$1/projects/p/$2.jsonl"
  mkdir -p "$(dirname "$f")"
  : > "$f"
  touch -t "$(date -r $((NOW - $3)) +%Y%m%d%H%M.%S)" "$f"
}

@test "古いワークスペースだけを閉じる" {
  state "$(ws wOld 🤖old false 1),$(ws wNew 🤖new false 1)" "$(ag wOld idle s-old),$(ag wNew idle s-new)"
  log_at acct1 s-old $((30 * DAY))
  log_at acct1 s-new $DAY
  run "$CMD"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TMPDIR/calls")" = "workspace close wOld" ]
  [ "$output" = "$(printf 'closed 🤖old 2026-01-30\nclosed 1')" ]
}

@test "ちょうど N 日前は閉じない" {
  state "$(ws wEdge 🤖edge false 1),$(ws wOver 🤖over false 1)" "$(ag wEdge idle s-edge),$(ag wOver idle s-over)"
  log_at acct1 s-edge $((14 * DAY))
  log_at acct1 s-over $((14 * DAY + 1))
  run "$CMD"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TMPDIR/calls")" = "workspace close wOver" ]
}

@test "フォーカス中は閉じない" {
  state "$(ws wOld 🤖old true 1)" "$(ag wOld idle s-old)"
  log_at acct1 s-old $((30 * DAY))
  run "$CMD"
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_TMPDIR/calls" ]
  [ "$output" = "closed 0" ]
}

@test "working・blocked・done がいれば閉じない" {
  log_at acct1 s-a $((30 * DAY))
  log_at acct1 s-b $((30 * DAY))
  for st in working blocked done; do
    state "$(ws wOld 🤖old false 2)" "$(ag wOld idle s-a),$(ag wOld "$st" s-b)"
    run "$CMD"
    echo "agent_status=$st"
    [ "$status" -eq 0 ]
    [ ! -e "$TEST_TMPDIR/calls" ]
    [ "$output" = "closed 0" ]
  done
}

@test "状態の分からないエージェントがいれば閉じない" {
  state "$(ws wOld 🤖old false 1)" "$(ag wOld unknown s-old)"
  log_at acct1 s-old $((30 * DAY))
  run "$CMD"
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_TMPDIR/calls" ]
  [ "$output" = "closed 0" ]
}

@test "シェルだけのペインがあれば閉じない" {
  state "$(ws wOld 🤖old false 2)" "$(ag wOld idle s-old)"
  log_at acct1 s-old $((30 * DAY))
  run "$CMD"
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_TMPDIR/calls" ]
  [ "$output" = "closed 0" ]
}

@test "エージェントもペインも無いワークスペースは閉じない" {
  state "$(ws wEmpty 🤖empty false 0)" ""
  run "$CMD"
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_TMPDIR/calls" ]
  [ "$output" = "closed 0" ]
}

@test "会話ログが見つからなければ閉じない" {
  state "$(ws wOld 🤖old false 2)" "$(ag wOld idle s-old),$(ag wOld idle s-gone)"
  log_at acct1 s-old $((30 * DAY))
  run "$CMD"
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_TMPDIR/calls" ]
  [ "$output" = "closed 0" ]
}

@test "もう一方のアカウントの会話ログも探す" {
  # The default roots, not the override.
  unset HERDR_CLOSE_STALE_ROOTS
  export HOME="$TEST_TMPDIR/home"
  state "$(ws wA 🤖a false 1),$(ws wB 🤖b false 1)" "$(ag wA idle s-a),$(ag wB idle s-b)"
  log_at home/.claude-private s-a $((30 * DAY))
  log_at home/.claude-work s-b $((30 * DAY))
  run "$CMD"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TMPDIR/calls")" = "$(printf 'workspace close wA\nworkspace close wB')" ]
}

@test "--dry-run は閉じずに候補だけ出す" {
  state "$(ws wOld 🤖old false 1)" "$(ag wOld idle s-old)"
  log_at acct1 s-old $((30 * DAY))
  run "$CMD" --dry-run
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_TMPDIR/calls" ]
  [ "$output" = "$(printf 'would close 🤖old 2026-01-30\nwould close 1')" ]
}

@test "--days で日数を変えられる" {
  state "$(ws wA 🤖a false 1),$(ws wB 🤖b false 1)" "$(ag wA idle s-a),$(ag wB idle s-b)"
  log_at acct1 s-a $((4 * DAY))
  log_at acct1 s-b $((2 * DAY))
  run "$CMD" --days 3
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TMPDIR/calls")" = "workspace close wA" ]
}

@test "不正な引数は使い方を出して 2 で終わる" {
  state "$(ws wOld 🤖old false 1)" "$(ag wOld idle s-old)"
  log_at acct1 s-old $((30 * DAY))
  for args in "--days 0" "--days x" "--days -1" "--days" "--bogus"; do
    # Unquoted on purpose: each entry is split into its words.
    run --separate-stderr "$CMD" $args
    echo "args=$args"
    [ "$status" -eq 2 ]
    [ -z "$output" ]
    printf '%s' "$stderr" | grep -qF "usage: herdr-close-stale"
  done
  [ ! -e "$TEST_TMPDIR/calls" ]
}

@test "1 つ閉じるのに失敗しても残りを閉じる" {
  state "$(ws wA 🤖a false 1),$(ws wB 🤖b false 1),$(ws wC 🤖c false 1)" \
    "$(ag wA idle s-a),$(ag wB idle s-b),$(ag wC idle s-c)"
  log_at acct1 s-a $((30 * DAY))
  log_at acct1 s-b $((30 * DAY))
  log_at acct1 s-c $((30 * DAY))
  export FAKE_CLOSE_FAIL=wB
  run "$CMD"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TMPDIR/calls")" = "$(printf 'workspace close wA\nworkspace close wB\nworkspace close wC')" ]
  printf '%s' "$output" | grep -qF "failed 🤖b"
  printf '%s' "$output" | grep -qF "herdr: cannot close wB"
  [ "$(printf '%s\n' "$output" | tail -n 1)" = "closed 2" ]
}

@test "herdr が無い・JSON が壊れていれば何もせず 0 で終わる" {
  good_ws="$(ws wOld 🤖old false 1)"
  good_ag="$(ag wOld idle s-old)"
  log_at acct1 s-old $((30 * DAY))

  state "$good_ws" "$good_ag"
  run env HERDR_BIN="$TEST_TMPDIR/missing" "$CMD"
  [ "$status" -eq 0 ]
  run env FAKE_WS_EXIT=1 "$CMD"
  [ "$status" -eq 0 ]
  run env FAKE_AGENTS_EXIT=1 "$CMD"
  [ "$status" -eq 0 ]

  for broken in "not json" '[]' '{"result":{}}' '{"result":{"workspaces":"x","agents":"x"}}'; do
    run env FAKE_WS="$broken" "$CMD"
    echo "workspaces=$broken"
    [ "$status" -eq 0 ]
    run env FAKE_AGENTS="$broken" "$CMD"
    echo "agents=$broken"
    [ "$status" -eq 0 ]
  done
  [ ! -e "$TEST_TMPDIR/calls" ]
}

@test "パスを含むセッション ID で別の会話ログを拾わない" {
  state "$(ws wOld 🤖old false 1)" "$(ag wOld idle ../p/s-old)"
  log_at acct1 s-old $((30 * DAY))
  run "$CMD"
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_TMPDIR/calls" ]
  [ "$output" = "closed 0" ]
}

@test "ラベルや ID に改行があっても別のワークスペースを閉じない" {
  # Each one ends in the focused workspace's id on a line of its own.
  state "$(ws wA '🤖a\nwKeep' false 1),$(ws 'wB\nwKeep' 🤖b false 1),$(ws wKeep 🤖keep true 1)" \
    "$(ag wA idle s-a),$(ag 'wB\nwKeep' idle s-b),$(ag wKeep idle s-keep)"
  log_at acct1 s-a $((30 * DAY))
  log_at acct1 s-b $((30 * DAY))
  log_at acct1 s-keep $((30 * DAY))
  run "$CMD"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TMPDIR/calls")" = "workspace close wA" ]
}
