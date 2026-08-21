#!/usr/bin/env bats
# Discord 実況リレーのテスト。
#
# 実況にはファイルパス・コマンド・ツール引数が載る。allowlist は安全機構なので
# 「通ること」ではなく「破ったら落ちること」を証明する必要がある。

load "helpers/common"

setup() {
  HOOK="$REPO_DIR/claude/hooks/discord-relay.sh"
  FLUSH="$REPO_DIR/bin/discord-relay-flush"
  export DISCORD_RELAY_ALLOWLIST="$BATS_TEST_TMPDIR/allowlist"
  export DISCORD_RELAY_SPOOL="$BATS_TEST_TMPDIR/spool"
  export DISCORD_RELAY_THREADS="$BATS_TEST_TMPDIR/threads"
  export HERDR_PANE_ID="wB:pD"

  ALLOWED="$BATS_TEST_TMPDIR/allowed"
  DENIED="$BATS_TEST_TMPDIR/denied"
  for d in "$ALLOWED" "$DENIED"; do
    mkdir -p "$d"
    git -C "$d" init -q
    git -C "$d" remote add origin "https://example.com/$(basename "$d").git"
  done
  printf 'https://example.com/allowed.git\n' > "$DISCORD_RELAY_ALLOWLIST"
}

# フックは stdin から JSON を受ける。
fire() {  # $1 = repo dir, $2 = event, $3 = tool_name, $4 = label
  printf '{"hook_event_name":"%s","tool_name":"%s"}' "$2" "${3:-}" \
    | CLAUDE_PROJECT_DIR="$1" bash "$HOOK" "${4:-}"
}

spool_lines() {
  grep -c . "$DISCORD_RELAY_SPOOL" 2>/dev/null || echo 0
}

@test "allowlist に載っている repo では 1 行追記される" {
  fire "$ALLOWED" PostToolUse Bash
  [ "$(spool_lines)" -eq 1 ]
  printf '%s' "$(cat "$DISCORD_RELAY_SPOOL")" | grep -qF 'wB:pD	PostToolUse	Bash'
}

@test "allowlist 外の repo では 1 行も書かれない" {
  fire "$DENIED" PostToolUse Bash
  [ "$(spool_lines)" -eq 0 ]
}

# この保証を実際に担っているのは allowlist 照合の grep（ファイルが無ければ grep が
# 失敗して exit 0 する）。フック側の -f チェックは git を起こさないための早期脱出で、
# 外しても本テストは通る。挙動を守っているのは grep 側だと理解して読むこと。
@test "allowlist ファイルが無ければ 1 行も書かれない" {
  rm -f "$DISCORD_RELAY_ALLOWLIST"
  fire "$ALLOWED" PostToolUse Bash
  [ "$(spool_lines)" -eq 0 ]
}

@test "remote を持たない作業ディレクトリでは書かれない" {
  bare="$BATS_TEST_TMPDIR/no-remote"
  mkdir -p "$bare"
  git -C "$bare" init -q
  fire "$bare" PostToolUse Bash
  [ "$(spool_lines)" -eq 0 ]
}

@test "Notification は第 1 引数をそのまま detail にする" {
  fire "$ALLOWED" Notification "" 'Waiting for approval'
  printf '%s' "$(cat "$DISCORD_RELAY_SPOOL")" | grep -qF 'wB:pD	Notification	Waiting for approval'
}

@test "ペイン未設定でも no-pane として記録する" {
  HERDR_PANE_ID='' fire "$ALLOWED" Stop "" 'done'
  printf '%s' "$(cat "$DISCORD_RELAY_SPOOL")" | grep -qF 'no-pane	Stop	done'
}

@test "フックは allowlist 外でも exit 0 を返す" {
  run fire "$DENIED" PostToolUse Bash
  [ "$status" -eq 0 ]
}
