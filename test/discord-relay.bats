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

# curl と security をスタブに差し替える。実際に Discord へ投げないため。
stub_bins() {  # $1 = webhook URL（空なら Keychain 未登録を再現）
  export SECURITY_BIN="$BATS_TEST_TMPDIR/security"
  export CURL_BIN="$BATS_TEST_TMPDIR/curl"
  if [ -n "${1:-}" ]; then
    printf '#!/bin/bash\nprintf "%%s" "%s"\n' "$1" > "$SECURITY_BIN"
  else
    printf '#!/bin/bash\nexit 1\n' > "$SECURITY_BIN"
  fi
  # 引数から URL を、-d の次の引数から body を拾って記録し、Discord の応答を模す。
  cat > "$CURL_BIN" <<'STUB'
#!/bin/bash
url=""; body=""
while [ $# -gt 0 ]; do
  case "$1" in
    https://*) url="$1" ;;
    -d) shift; body="$1" ;;
  esac
  shift
done
printf '%s\n' "$url"  >> "$BATS_TEST_TMPDIR/posts.url"
printf '%s\n' "$body" >> "$BATS_TEST_TMPDIR/posts.body"
printf '{"channel_id":"9999"}'
STUB
  chmod +x "$SECURITY_BIN" "$CURL_BIN"
}

posts() { grep -c . "$BATS_TEST_TMPDIR/posts.url" 2>/dev/null || echo 0; }

@test "webhook URL 未登録ならスプールを消さず何も送らない" {
  fire "$ALLOWED" PostToolUse Bash
  stub_bins ""
  run bash "$FLUSH"
  [ "$status" -eq 0 ]
  [ "$(spool_lines)" -eq 1 ]
  [ "$(posts)" -eq 0 ]
}

# allowlist を設定してから webhook を登録するまでの間、スプールを排出する者がいない。
# フックは Keychain を見られない（ツール実行のたびに security を起動することになる）ので、
# 上限はタイマーが既に回っているフラッシュ側で掛ける。
@test "webhook 未登録でもスプールは上限を超えて育たない" {
  i=0
  while [ "$i" -lt 1200 ]; do
    printf 'wB:pD\tPostToolUse\tBash\n' >> "$DISCORD_RELAY_SPOOL"
    i=$((i + 1))
  done
  stub_bins ""
  run bash "$FLUSH"
  [ "$status" -eq 0 ]
  n=$(spool_lines)
  [ "$n" -le 1000 ]
  # 直近が残ること（先頭を捨てて末尾を残す）
  [ "$n" -gt 0 ]
}

@test "PostToolUse は 1 通に畳まれ、ツール名と件数が出る" {
  fire "$ALLOWED" PostToolUse Bash
  fire "$ALLOWED" PostToolUse Bash
  fire "$ALLOWED" PostToolUse Edit
  stub_bins "https://discord.example/api/webhooks/1/tok"
  run bash "$FLUSH"
  [ "$status" -eq 0 ]
  [ "$(posts)" -eq 1 ]
  b=$(grep -cF 'Bash x2' "$BATS_TEST_TMPDIR/posts.body") || b=0
  e=$(grep -cF 'Edit x1' "$BATS_TEST_TMPDIR/posts.body") || e=0
  [ "$b" -eq 1 ]
  [ "$e" -eq 1 ]
}

@test "Notification は畳まれず本文に残る" {
  fire "$ALLOWED" Notification "" 'Waiting for approval'
  fire "$ALLOWED" PostToolUse Bash
  stub_bins "https://discord.example/api/webhooks/1/tok"
  run bash "$FLUSH"
  n=$(grep -cF 'Waiting for approval' "$BATS_TEST_TMPDIR/posts.body") || n=0
  [ "$n" -eq 1 ]
}

# 切り詰めはフラッシュの性質なので、フックを 400 回起こさずスプールを直接書く。
# フック経由にすると 1 テストで 1200 プロセスを起動して十数秒かかる。
@test "2000 文字を超える本文は行単位で切り詰められる" {
  i=0
  while [ "$i" -lt 400 ]; do
    printf 'wB:pD\tNotification\tlong-line-%s-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n' "$i" >> "$DISCORD_RELAY_SPOOL"
    i=$((i + 1))
  done
  stub_bins "https://discord.example/api/webhooks/1/tok"
  run bash "$FLUSH"
  [ "$status" -eq 0 ]
  longest=$(awk '{ if (length($0) > m) m = length($0) } END { print m+0 }' "$BATS_TEST_TMPDIR/posts.body")
  [ "$longest" -lt 2200 ]
  t=$(grep -cF '(truncated)' "$BATS_TEST_TMPDIR/posts.body") || t=0
  [ "$t" -eq 1 ]
}

@test "フラッシュ後にスプールは空になる" {
  fire "$ALLOWED" PostToolUse Bash
  stub_bins "https://discord.example/api/webhooks/1/tok"
  run bash "$FLUSH"
  [ "$(spool_lines)" -eq 0 ]
}

@test "スプールが空なら何も送らない" {
  stub_bins "https://discord.example/api/webhooks/1/tok"
  run bash "$FLUSH"
  [ "$status" -eq 0 ]
  [ "$(posts)" -eq 0 ]
}

@test "初回はスレッドを作り、2 通目は thread_id を再利用する" {
  stub_bins "https://discord.example/api/webhooks/1/tok"

  fire "$ALLOWED" PostToolUse Bash
  run bash "$FLUSH"
  first=$(grep -cF 'wait=true' "$BATS_TEST_TMPDIR/posts.url") || first=0
  [ "$first" -eq 1 ]

  fire "$ALLOWED" PostToolUse Edit
  run bash "$FLUSH"
  reuse=$(grep -cF 'thread_id=9999' "$BATS_TEST_TMPDIR/posts.url") || reuse=0
  [ "$reuse" -eq 1 ]

  # 新規作成は 1 回だけ。2 通目でスレッドを作り直していない。
  creates=$(grep -cF 'wait=true' "$BATS_TEST_TMPDIR/posts.url") || creates=0
  [ "$creates" -eq 1 ]
}

@test "ペインが 2 つあれば 2 通に分かれる" {
  stub_bins "https://discord.example/api/webhooks/1/tok"
  fire "$ALLOWED" PostToolUse Bash
  HERDR_PANE_ID='wA:pA' fire "$ALLOWED" PostToolUse Read
  run bash "$FLUSH"
  [ "$(posts)" -eq 2 ]
}

# 配線が無ければフックは一度も呼ばれない。実装があることと配線があることは別。
@test "settings.json が Notification と Stop にフックを配線している" {
  s="$REPO_DIR/claude/settings.json"
  run jq -r '[.hooks | to_entries[] | select(any(.value[].hooks[].command; test("discord-relay"))) | .key] | sort | join(",")' "$s"
  [ "$output" = "Notification,Stop" ]
}

# PostToolUse を配線しないのは意図的な選択で、書き忘れではない。実測すると 10 秒間隔の
# フラッシュでも約 6 分で 8 通に達し、肝心の承認待ち通知がツール実況に埋もれた。遠隔から
# 必要なのは「止まったかどうか」であって逐次のツール実行ではない。
#
# 戻したくなったら matcher "*" のエントリを 1 つ足すだけでよい。フラッシュ側の集約
# （Bash x2 に畳む処理）は残してあるので実装変更は要らない。
#
# 副次的な利点として、毎ツール呼び出しごとのプロセス起動がゼロになる。
@test "PostToolUse には配線しない" {
  s="$REPO_DIR/claude/settings.json"
  n=$(jq -r '[.hooks.PostToolUse[]?.hooks[]?.command | select(test("discord-relay"))] | length' "$s")
  [ "$n" -eq 0 ]
}

@test "Notification の 3 matcher すべてに配線されている" {
  s="$REPO_DIR/claude/settings.json"
  run jq -r '[.hooks.Notification[] | select(any(.hooks[].command; test("discord-relay"))) | .matcher] | sort | join(",")' "$s"
  [ "$output" = "elicitation_dialog,idle_prompt,permission_prompt" ]
}

@test "plist が 10 秒間隔でフラッシュを起動する" {
  p="$REPO_DIR/macos/com.snakashima.discord-relay-flush.plist"
  run plutil -extract StartInterval raw "$p"
  [ "$output" = "10" ]
  n=$(plutil -extract ProgramArguments.0 raw "$p" | grep -cF 'discord-relay-flush') || n=0
  [ "$n" -eq 1 ]
}

@test "setup が LaunchAgent と allowlist を用意する" {
  f="$REPO_DIR/setup/install.zsh"
  n=$(grep -cF 'com.snakashima.discord-relay-flush' "$f") || n=0
  a=$(grep -cF 'discord-relay/allowlist' "$f") || a=0
  k=$(grep -cF 'claude-discord-webhook' "$f") || k=0
  [ "$n" -ge 1 ]
  [ "$a" -ge 1 ]
  [ "$k" -ge 1 ]
}
