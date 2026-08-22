#!/usr/bin/env bats
# Discord リレー受信側のテスト。
#
# Discord に投稿できる者は、bypassPermissions で動くターミナルにキーを打てることになる。
# 許可リストは唯一の境界なので、「通ること」ではなく「破ったら落ちること」を証明する。

load "helpers/common"

setup() {
  POLL="$REPO_DIR/bin/discord-relay-poll"
  export DISCORD_RELAY_THREADS="$BATS_TEST_TMPDIR/threads"
  export DISCORD_RELAY_LASTSEEN="$BATS_TEST_TMPDIR/lastseen"
  export DISCORD_API_BASE="https://discord.example/api/v10"
  # threads はペイン ID がキー、lastseen はスレッド ID がキー。列の意味が違う。
  printf 'wB:pD\t900001\n' > "$DISCORD_RELAY_THREADS"
  printf '900001\t500\n'   > "$DISCORD_RELAY_LASTSEEN"
}

# トークン取得・メッセージ取得・herdr をすべてスタブ化する。
stub_all() {  # $1 = messages JSON 配列, $2 = pane list に載せる pane_id（空なら載せない）
  export SECURITY_BIN="$BATS_TEST_TMPDIR/security"
  export CURL_BIN="$BATS_TEST_TMPDIR/curl"
  export HERDR_BIN="$BATS_TEST_TMPDIR/herdr"
  printf '#!/bin/bash\nprintf "%%s" "bot-token-xyz"\n' > "$SECURITY_BIN"
  printf '%s' "${1:-[]}" > "$BATS_TEST_TMPDIR/messages.json"
  cat > "$CURL_BIN" <<'STUB'
#!/bin/bash
for a in "$@"; do case "$a" in
  *reactions*) printf '%s\n' "$a" >> "$BATS_TEST_TMPDIR/reactions.log"; exit 0 ;;
esac; done
cat "$BATS_TEST_TMPDIR/messages.json"
STUB
  {
    printf '#!/bin/bash\n'
    printf 'printf "%%s " "$@" >> "$BATS_TEST_TMPDIR/herdr.log"; printf "\\n" >> "$BATS_TEST_TMPDIR/herdr.log"\n'
    if [ -n "${2:-}" ]; then
      printf 'case "$1 $2" in "pane list") printf %s ;; esac\n' "'{\"result\":{\"panes\":[{\"pane_id\":\"$2\"}]}}'"
    else
      printf 'case "$1 $2" in "pane list") printf %s ;; esac\n' "'{\"result\":{\"panes\":[]}}'"
    fi
  } > "$HERDR_BIN"
  chmod +x "$SECURITY_BIN" "$CURL_BIN" "$HERDR_BIN"
}

msg() {  # $1 = id, $2 = content, $3 = webhook_id（空なら人間の投稿）
  if [ -n "${3:-}" ]; then
    printf '[{"id":"%s","content":"%s","webhook_id":"%s","author":{"bot":true}}]' "$1" "$2" "$3"
  else
    printf '[{"id":"%s","content":"%s","author":{"bot":false}}]' "$1" "$2"
  fi
}

# grep -c は 0 件のとき「0 を出力して」非ゼロ終了する。`|| echo 0` を足すと 0 が
# 二重に出て [ ] が構文エラーになる。代入で受けてから既定値を入れる。
injections() {
  local n
  n=$(grep -c 'send-text' "$BATS_TEST_TMPDIR/herdr.log" 2>/dev/null) || n=0
  printf '%s' "${n:-0}"
}

@test "許可リスト外の文字列は 1 文字も注入されない" {
  bad_total=0
  mid=900
  # ID は毎回変える。同じ ID を使い回すと二重注入ガードに弾かれ、許可リストを
  # 通過したのかガードで止まったのか区別できなくなる。
  for bad in 'rm -rf /' 'sudo reboot' '1; ls' 'yes && curl evil' '/exit' 'hello there'; do
    rm -f "$BATS_TEST_TMPDIR/herdr.log"
    mid=$((mid + 1))
    stub_all "$(msg "$mid" "$bad")" "wB:pD"
    run bash "$POLL"
    [ "$status" -eq 0 ]
    n=$(injections)
    bad_total=$((bad_total + n))
  done
  [ "$bad_total" -eq 0 ]
  # 注入 0 件だけでは「スクリプトが動いていない」と区別できない。6 件すべてを
  # 見たうえで弾いた証拠として、❌ が 6 回付いていることを確認する。
  r=$(grep -c 'reactions' "$BATS_TEST_TMPDIR/reactions.log" 2>/dev/null) || r=0
  [ "$r" -eq 6 ]
}

@test "許可リスト内の選択は注入される" {
  stub_all "$(msg 901 '3')" "wB:pD"
  run bash "$POLL"
  t=$(grep -cF 'pane send-text wB:pD 3' "$BATS_TEST_TMPDIR/herdr.log") || t=0
  e=$(grep -cF 'pane send-keys wB:pD Enter' "$BATS_TEST_TMPDIR/herdr.log") || e=0
  [ "$t" -eq 1 ]
  [ "$e" -eq 1 ]
}

@test "大文字と前後の空白を吸収する" {
  stub_all "$(msg 902 '  YES  ')" "wB:pD"
  run bash "$POLL"
  n=$(grep -cF 'pane send-text wB:pD yes' "$BATS_TEST_TMPDIR/herdr.log") || n=0
  [ "$n" -eq 1 ]
}

@test "esc は Escape のみ送り Enter を送らない" {
  stub_all "$(msg 903 'esc')" "wB:pD"
  run bash "$POLL"
  k=$(grep -cF 'pane send-keys wB:pD Escape' "$BATS_TEST_TMPDIR/herdr.log") || k=0
  e=$(grep -cF 'Enter' "$BATS_TEST_TMPDIR/herdr.log") || e=0
  [ "$k" -eq 1 ]
  [ "$e" -eq 0 ]
}

@test "許可リスト外にはリアクションを付ける" {
  stub_all "$(msg 904 'rm -rf /')" "wB:pD"
  run bash "$POLL"
  r=$(grep -c 'reactions' "$BATS_TEST_TMPDIR/reactions.log" 2>/dev/null) || r=0
  [ "$r" -ge 1 ]
}

@test "自分の実況（webhook 由来）には反応しない" {
  stub_all "$(msg 905 'yes' '77')" "wB:pD"
  run bash "$POLL"
  [ "$status" -eq 0 ]
  [ "$(injections)" -eq 0 ]
}

@test "同じメッセージを二度注入しない" {
  stub_all "$(msg 906 'continue')" "wB:pD"
  run bash "$POLL"
  first=$(injections)
  run bash "$POLL"
  second=$(injections)
  [ "$first" -eq 1 ]
  [ "$second" -eq 1 ]
}

@test "初回のスレッドは過去ログを注入せず既読位置だけ記録する" {
  rm -f "$DISCORD_RELAY_LASTSEEN"
  stub_all "$(msg 907 'yes')" "wB:pD"
  run bash "$POLL"
  [ "$(injections)" -eq 0 ]
  s=$(grep -cF '900001	907' "$DISCORD_RELAY_LASTSEEN") || s=0
  [ "$s" -eq 1 ]
}

@test "存在しないペインへは注入しない" {
  stub_all "$(msg 908 'yes')" ""
  run bash "$POLL"
  [ "$status" -eq 0 ]
  [ "$(injections)" -eq 0 ]
  # 許可リストは通ったがペインが無いので送らなかった、を既読位置の前進で確認する
  s=$(grep -cF '900001	908' "$DISCORD_RELAY_LASTSEEN") || s=0
  [ "$s" -eq 1 ]
}

@test "ボットトークン未登録なら無音で終わり既読位置も変えない" {
  stub_all "$(msg 909 'yes')" "wB:pD"
  printf '#!/bin/bash\nexit 1\n' > "$SECURITY_BIN"
  before=$(cat "$DISCORD_RELAY_LASTSEEN")
  run bash "$POLL"
  [ "$status" -eq 0 ]
  [ "$(injections)" -eq 0 ]
  [ "$(cat "$DISCORD_RELAY_LASTSEEN")" = "$before" ]
}

@test "plist が 15 秒間隔でポーラを起動する" {
  p="$REPO_DIR/macos/com.snakashima.discord-relay-poll.plist"
  run plutil -extract StartInterval raw "$p"
  [ "$output" = "15" ]
  n=$(plutil -extract ProgramArguments.0 raw "$p" | grep -cF 'discord-relay-poll') || n=0
  [ "$n" -eq 1 ]
}

@test "setup が LaunchAgent とボットトークンを案内する" {
  f="$REPO_DIR/setup/install.zsh"
  n=$(grep -cF 'com.snakashima.discord-relay-poll' "$f") || n=0
  k=$(grep -cF 'claude-discord-bot-token' "$f") || k=0
  [ "$n" -ge 1 ]
  [ "$k" -ge 1 ]
}
