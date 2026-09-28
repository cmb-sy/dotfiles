#!/usr/bin/env bats
# bin/distill-record-sweep のテスト。
#
# 開いたままのセッションを記録に回す巡回。どの transcript をいつ渡すか、
# 1 回に何件書かせるか、どのアカウントで LLM を起こすかをここで固定する。
# 渡した先の判定はフック側のテスト（hooks-distill-record.bats）が見る。

load "helpers/common"

SWEEP="${BATS_TEST_DIRNAME}/../bin/distill-record-sweep"
HOOK="${BATS_TEST_DIRNAME}/../claude/hooks/distill-record.sh"

setup() {
  make_tmpdir
  FAKE_HOME="$TEST_TMPDIR/home"
  ACCT_A="$TEST_TMPDIR/acct-a"
  ACCT_B="$TEST_TMPDIR/acct-b"
  mkdir -p "$FAKE_HOME" "$ACCT_A/projects/p" "$ACCT_B/projects/p"
  CALLS="$TEST_TMPDIR/hook-calls"
  # 受け取った入力と環境を 1 行に残すだけのフック。
  cat >"$TEST_TMPDIR/fake-hook.sh" <<'SH'
#!/bin/bash
sid=$(/usr/bin/python3 -c 'import json,sys;print(json.load(sys.stdin)["session_id"])')
tok=unset
[ -n "${CLAUDE_CODE_OAUTH_TOKEN+x}" ] && tok="$CLAUDE_CODE_OAUTH_TOKEN"
printf '%s %s %s %s\n' "$sid" "$(basename "$CLAUDE_CONFIG_DIR")" "$tok" "${DISTILL_RECORD_FOREGROUND:-}" >>"$CALLS"
exit "${FAKE_HOOK_RC:-0}"
SH
  chmod +x "$TEST_TMPDIR/fake-hook.sh"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

# <分> 前の時刻（transcript の timestamp の形）。
ago() { date -u -v-"${1}"M +%Y-%m-%dT%H:%M:%S.000Z; }

# 最後の会話が <分> 前の transcript を置く。更新時刻も同じにする。
put_tx() {
  local path="$1" minutes="$2"
  mkdir -p "$(dirname "$path")"
  printf '{"type":"user","timestamp":"%s","message":{"content":"x"}}\n' "$(ago "$minutes")" >"$path"
  touch -t "$(date -v-"${minutes}"M +%Y%m%d%H%M)" "$path"
}

run_sweep() {
  run env HOME="$FAKE_HOME" CALLS="$CALLS" \
    DISTILL_SWEEP_HOOK="$TEST_TMPDIR/fake-hook.sh" \
    DISTILL_SWEEP_ACCOUNTS="$ACCT_A:$ACCT_B" "$@" "$SWEEP"
}

called() { local n; n=$(grep -c "^$1 " "$CALLS" 2>/dev/null) || true; echo "${n:-0}"; }

@test "sweep: 更新が止まって一定時間たった transcript だけを渡す" {
  put_tx "$ACCT_A/projects/p/idle.jsonl" 180
  put_tx "$ACCT_A/projects/p/busy.jsonl" 10
  put_tx "$ACCT_A/projects/p/ancient.jsonl" $((60 * 24 * 10))
  # サブエージェントの transcript は本体の下にある。会話の本体ではない。
  put_tx "$ACCT_A/projects/p/idle/subagents/agent-1.jsonl" 180
  run_sweep
  [ "$status" -eq 0 ]
  [ "$(called idle)" -eq 1 ]
  [ "$(called busy)" -eq 0 ]
  [ "$(called ancient)" -eq 0 ]
  [ "$(called agent-1)" -eq 0 ]
}

@test "sweep: 会話が止まっていれば、管理用の行で更新時刻が新しくても渡す" {
  # 開いたままのセッションは会話が無くても mode や last-prompt を足し続ける。
  # 更新時刻で見ると、いつまでも作業中に見えて永久に拾えない。
  put_tx "$ACCT_A/projects/p/open.jsonl" 180
  printf '%s\n' '{"type":"mode","mode":"normal","sessionId":"open"}' >>"$ACCT_A/projects/p/open.jsonl"
  run_sweep
  [ "$(called open)" -eq 1 ]
}

@test "sweep: 会話が続いていれば、更新時刻が古くても渡さない" {
  put_tx "$ACCT_A/projects/p/talking.jsonl" 10
  touch -t "$(date -v-300M +%Y%m%d%H%M)" "$ACCT_A/projects/p/talking.jsonl"
  run_sweep
  [ "$(called talking)" -eq 0 ]
}

@test "sweep: 前景で書かせる（書き込みを待ってから次へ進む）" {
  put_tx "$ACCT_A/projects/p/idle.jsonl" 180
  run_sweep
  grep -qE '^idle acct-a [^ ]+ 1$' "$CALLS"
}

@test "sweep: 止まってから長いものを先に渡す" {
  put_tx "$ACCT_A/projects/p/newer.jsonl" 180
  put_tx "$ACCT_A/projects/p/older.jsonl" 300
  run_sweep
  [ "$(sed -n 1p "$CALLS" | cut -d' ' -f1)" = "older" ]
  [ "$(sed -n 2p "$CALLS" | cut -d' ' -f1)" = "newer" ]
}

@test "sweep: 書かせた件数が上限に達したら残りは次の巡回に回す" {
  put_tx "$ACCT_A/projects/p/a.jsonl" 300
  put_tx "$ACCT_A/projects/p/b.jsonl" 240
  put_tx "$ACCT_B/projects/p/c.jsonl" 180
  run_sweep FAKE_HOOK_RC=10 DISTILL_SWEEP_MAX=2
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$CALLS" | tr -d ' ')" -eq 2 ]
  grep -qF "上限 2 件" "$FAKE_HOME/.distill/logs/record.log"
}

@test "sweep: 判定で落ちた候補は上限に数えない" {
  put_tx "$ACCT_A/projects/p/a.jsonl" 300
  put_tx "$ACCT_A/projects/p/b.jsonl" 240
  put_tx "$ACCT_B/projects/p/c.jsonl" 180
  run_sweep FAKE_HOOK_RC=0 DISTILL_SWEEP_MAX=1
  [ "$(wc -l <"$CALLS" | tr -d ' ')" -eq 3 ]
}

@test "sweep: transcript のあるアカウントの設定とトークンで動かす" {
  # 手元の clp / clw と同じ。別アカウントのトークンは持ち込まない。
  put_tx "$ACCT_A/projects/p/in-a.jsonl" 180
  put_tx "$ACCT_B/projects/p/in-b.jsonl" 180
  printf 'token-a' >"$ACCT_A/oauth-token"
  run_sweep CLAUDE_CODE_OAUTH_TOKEN=leaked CLAUDE_CONFIG_DIR=/elsewhere
  grep -qE '^in-a acct-a token-a ' "$CALLS"
  grep -qE '^in-b acct-b unset ' "$CALLS"
}

@test "sweep: 無いアカウントは飛ばす" {
  put_tx "$ACCT_A/projects/p/idle.jsonl" 180
  run env HOME="$FAKE_HOME" CALLS="$CALLS" DISTILL_SWEEP_HOOK="$TEST_TMPDIR/fake-hook.sh" \
    DISTILL_SWEEP_ACCOUNTS="$TEST_TMPDIR/nope:$ACCT_A" "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(called idle)" -eq 1 ]
}

@test "sweep: 1 以上の整数でない設定は拒否する" {
  put_tx "$ACCT_A/projects/p/idle.jsonl" 180
  local bad
  for bad in "DISTILL_SWEEP_MAX=abc" "DISTILL_SWEEP_MAX=0" "DISTILL_SWEEP_IDLE_MIN=1.5" \
    "DISTILL_SWEEP_LOOKBACK_DAYS=-1" "DISTILL_SWEEP_INTERVAL_MIN=0"; do
    run_sweep "$bad"
    [ "$status" -eq 2 ]
  done
  [ ! -e "$CALLS" ]
}

@test "sweep: 本物のフックとつなぐと 1 回だけ書かせる" {
  # 巡回とフックの取り決め（前景・終了コード 10・判定済みの記憶）を通しで見る。
  # claude は偽物。起動された回数と、書いた記録を見る。
  local repo tx
  repo="$(make_tmp_git_repo)"
  tx="$ACCT_A/projects/p/sweep-integration-session.jsonl"
  mkdir -p "$(dirname "$tx")" "$TEST_TMPDIR/bin"
  local at
  at="$(ago 180)"
  {
    printf '{"type":"user","cwd":"%s","timestamp":"%s","message":{"content":"直してください"}}\n' "$repo" "$at"
    printf '{"type":"assistant","timestamp":"%s","message":{"content":[{"type":"text","text":"直しました"}]}}\n' "$at"
    printf '{"type":"assistant","timestamp":"%s","message":{"content":[{"type":"tool_use","name":"Edit"}]}}\n' "$at"
    printf '{"type":"assistant","timestamp":"%s","message":{"content":[{"type":"tool_use","name":"Edit"}]}}\n' "$at"
    printf '{"type":"assistant","timestamp":"%s","message":{"content":[{"type":"tool_use","name":"Write"}]}}\n' "$at"
  } >"$tx"
  touch -t "$(date -v-180M +%Y%m%d%H%M)" "$tx"
  cat >"$TEST_TMPDIR/bin/claude" <<'SH'
#!/bin/bash
echo x >>"$CALLS"
sid=$(printf '%s' "$2" | sed -n 's/.*session には \([A-Za-z0-9_-]*\) を.*/\1/p')
dest="$HOME/develop/distill-vault/プロジェクト/$(basename "$PWD")/記録"
mkdir -p "$dest"
printf -- '---\nsession: %s\n---\n' "$sid" >"$dest/2026-01-01-0000.md"
SH
  chmod +x "$TEST_TMPDIR/bin/claude"
  local i
  for i in 1 2 3; do
    run env HOME="$FAKE_HOME" CALLS="$CALLS" PATH="$TEST_TMPDIR/bin:$PATH" \
      DISTILL_SWEEP_HOOK="$HOOK" DISTILL_SWEEP_ACCOUNTS="$ACCT_A" "$SWEEP"
    [ "$status" -eq 0 ]
    # 2 回目の前に管理用の行を足す。会話が伸びていないので書かせ直さない。
    printf '%s\n' '{"type":"mode","mode":"normal"}' >>"$tx"
  done
  [ "$(wc -l <"$CALLS" | tr -d ' ')" -eq 1 ]
  grep -qF "sweep-integration-session: 記録を書いた" "$FAKE_HOME/.distill/logs/record.log"
  rm -rf "$repo"
}

@test "sweep: ブロックしたアカウントは走査しない" {
  put_tx "$ACCT_A/projects/p/in-a.jsonl" 180
  put_tx "$ACCT_B/projects/p/in-b.jsonl" 180
  printf '%s\n' "$ACCT_A" >"$TEST_TMPDIR/blocklist"
  run_sweep DISTILL_RECORD_BLOCKLIST="$TEST_TMPDIR/blocklist"
  [ "$status" -eq 0 ]
  [ "$(called in-a)" -eq 0 ]
  [ "$(called in-b)" -eq 1 ]
}

@test "sweep: ブロックリストを読めなければ何も走査しない" {
  put_tx "$ACCT_A/projects/p/in-a.jsonl" 180
  run_sweep DISTILL_RECORD_BLOCKLIST="$TEST_TMPDIR/nope"
  [ "$status" -eq 0 ]
  [ ! -e "$CALLS" ]
}

# --- Stop フックからの入口（--kick）--------------------------------------

# --kick を走らせる。切り離された巡回もこの環境を引き継ぐ。
kick() {
  env HOME="$FAKE_HOME" CALLS="$CALLS" DISTILL_SWEEP_HOOK="$TEST_TMPDIR/fake-hook.sh" \
    DISTILL_SWEEP_ACCOUNTS="$ACCT_A:$ACCT_B" "$@" "$SWEEP" --kick </dev/null
}

# 切り離された巡回が終わるまで待つ（ロックが消えるまで）。後片付けの前に
# 終わらせないと、消したディレクトリへ書き込みに来る。
wait_sweep() {
  local i lock="$FAKE_HOME/.distill/state/sweep.lock"
  for i in $(seq 1 100); do
    [ -e "$CALLS" ] && [ ! -e "$lock" ] && return 0
    sleep 0.1
  done
  return 1
}

@test "sweep: --kick は巡回を裏で起こし、終わるのを待たずに返す" {
  # 応答の後処理を LLM の書き込みで待たせない。
  put_tx "$ACCT_A/projects/p/idle.jsonl" 180
  printf '#!/bin/bash\nsleep 2\nexec %s\n' "$TEST_TMPDIR/fake-hook.sh" >"$TEST_TMPDIR/slow-hook.sh"
  chmod +x "$TEST_TMPDIR/slow-hook.sh"
  local t0 t1
  t0=$(date +%s)
  env HOME="$FAKE_HOME" CALLS="$CALLS" DISTILL_SWEEP_HOOK="$TEST_TMPDIR/slow-hook.sh" \
    DISTILL_SWEEP_ACCOUNTS="$ACCT_A" "$SWEEP" --kick </dev/null
  t1=$(date +%s)
  [ $((t1 - t0)) -le 1 ]
  wait_sweep
  [ "$(called idle)" -eq 1 ]
}

@test "sweep: --kick は前回から間が空いていなければ何もしない" {
  put_tx "$ACCT_A/projects/p/idle.jsonl" 180
  mkdir -p "$FAKE_HOME/.distill/state"
  touch "$FAKE_HOME/.distill/state/sweep.kicked"
  kick
  sleep 1
  [ ! -e "$CALLS" ]
}

@test "sweep: --kick は間隔を過ぎていれば起こす" {
  put_tx "$ACCT_A/projects/p/idle.jsonl" 180
  mkdir -p "$FAKE_HOME/.distill/state"
  touch -t "$(date -v-31M +%Y%m%d%H%M)" "$FAKE_HOME/.distill/state/sweep.kicked"
  kick
  wait_sweep
  [ "$(called idle)" -eq 1 ]
  # 起こした時刻を残す。次の応答ではもう起こさない。
  [ -n "$(find "$FAKE_HOME/.distill/state/sweep.kicked" -mmin -1)" ]
}

@test "sweep: 巡回は 1 本だけ走る" {
  # 応答が重なって 2 本起きても、後から来たほうは何もしない。
  put_tx "$ACCT_A/projects/p/idle.jsonl" 180
  mkdir -p "$FAKE_HOME/.distill/state/sweep.lock"
  run_sweep
  [ "$status" -eq 0 ]
  [ ! -e "$CALLS" ]
  # 他人のロックは消さない。
  [ -d "$FAKE_HOME/.distill/state/sweep.lock" ]
}

@test "sweep: 取り残された巡回のロックは 3 時間で見限る" {
  put_tx "$ACCT_A/projects/p/idle.jsonl" 180
  mkdir -p "$FAKE_HOME/.distill/state/sweep.lock"
  touch -t "$(date -v-181M +%Y%m%d%H%M)" "$FAKE_HOME/.distill/state/sweep.lock"
  run_sweep
  [ "$(called idle)" -eq 1 ]
  [ ! -e "$FAKE_HOME/.distill/state/sweep.lock" ]
}
