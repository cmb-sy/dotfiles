#!/usr/bin/env bats
# Typeless truncates one dictation at a fixed number of characters, so the
# watcher hands the next dictation to Handy once one comes close. These run
# against a stub database, a stub voice-switch (the real one quits and
# relaunches apps) and a stub pgrep (which decides whether Typeless is running).

load "helpers/common"

setup() {
  WATCH="$REPO_DIR/bin/voice-length-watch"
  export VOICE_LENGTH_STATE="$BATS_TEST_TMPDIR/state"
  export VOICE_LENGTH_CONF="$BATS_TEST_TMPDIR/length.conf"
  export SQLITE_BIN=/usr/bin/sqlite3
  export VOICE_SWITCH_BIN="$BATS_TEST_TMPDIR/voice-switch"
  export OSASCRIPT_BIN=/usr/bin/true
  printf '#!/bin/bash\necho "SWITCH: $*" >> "%s/switches"\n' "$BATS_TEST_TMPDIR" > "$VOICE_SWITCH_BIN"
  chmod +x "$VOICE_SWITCH_BIN"
  # Typeless running by default: that is the state in which a switch is wanted.
  export PGREP_BIN="$BATS_TEST_TMPDIR/pgrep"
  typeless_is running
  DB="$BATS_TEST_TMPDIR/typeless.db"
  /usr/bin/sqlite3 "$DB" "CREATE TABLE history_v2 (id TEXT, refined_text TEXT, status TEXT, created_at TEXT);"
}

typeless_is() {  # running | stopped
  if [ "$1" = running ]; then
    printf '#!/bin/bash\nexit 0\n' > "$PGREP_BIN"
  else
    printf '#!/bin/bash\nexit 1\n' > "$PGREP_BIN"
  fi
  chmod +x "$PGREP_BIN"
}

# A dictation of exactly $2 characters. $3 is an sqlite date expression,
# default now. hex(zeroblob(n)) yields 2n characters, so an odd length has to be
# cut back down -- without the substr, a one-below-threshold fixture seeds as
# the threshold itself and the boundary test asserts the wrong number.
seed() {  # $1 = id, $2 = length, $3 = when (optional), $4 = status (optional)
  /usr/bin/sqlite3 "$DB" "INSERT INTO history_v2 VALUES (
    '$1', substr(replace(hex(zeroblob(($2 + 1) / 2)), '0', 'a'), 1, $2),
    '${4:-completed}', strftime('%Y-%m-%dT%H:%M:%SZ','${3:-now}'));"
}

write_conf() { printf 'TYPELESS_LENGTH_LIMIT=%s\n' "$1" > "$VOICE_LENGTH_CONF"; }

run_watch() { run bash -c "TYPELESS_DB='$DB' '$WATCH' 2>&1"; }

switches() { cat "$BATS_TEST_TMPDIR/switches" 2>/dev/null || true; }
switch_count() {
  local n
  n=$(switches | grep -c .) || n=0
  printf '%s' "$n"
}

@test "初回は基準点を置くだけで切り替えない" {
  # 状態ファイルが無い時点で最新行に反応すると、何か月も前の長い書き起こしを
  # 「今起きたこと」として拾ってしまう。
  write_conf 1900
  seed old 2000 '-60 days'
  run_watch
  [ "$(switch_count)" -eq 0 ]
  printf '%s' "$output" | grep -qF 'first run'
  cat "$VOICE_LENGTH_STATE" | grep -qF 'old'
}

@test "閾値を超えた新しい書き起こしで Handy へ切り替える" {
  write_conf 1900
  seed first 100 '-1 hours'
  run_watch
  seed long 1950
  run_watch
  switches | grep -qF 'SWITCH: local'
}

@test "閾値ちょうどでも切り替える" {
  write_conf 1900
  seed first 100 '-1 hours'
  run_watch
  seed exact 1900
  run_watch
  switches | grep -qF 'SWITCH: local'
}

@test "閾値に 1 文字足りなければ切り替えない" {
  write_conf 1900
  seed first 100 '-1 hours'
  run_watch
  seed nearly 1899
  run_watch
  [ "$(switch_count)" -eq 0 ]
}

@test "同じ書き起こしで二度は切り替えない" {
  write_conf 1900
  seed first 100 '-1 hours'
  run_watch
  seed long 1950
  run_watch
  run_watch
  run_watch
  [ "$(switch_count)" -eq 1 ]
}

@test "Typeless が動いていなければ切り替えない" {
  # 既に Handy なら Typeless は終了しており、この行は新しくない。切り替えると
  # 入力中のアプリを終了させてしまう。
  write_conf 1900
  seed first 100 '-1 hours'
  run_watch
  typeless_is stopped
  seed long 1950
  run_watch
  [ "$(switch_count)" -eq 0 ]
  printf '%s' "$output" | grep -qF 'leaving the engine alone'
}

@test "未完了の書き起こしは見ない" {
  write_conf 1900
  seed first 100 '-1 hours'
  run_watch
  seed dropped 2000 'now' dismissed
  run_watch
  [ "$(switch_count)" -eq 0 ]
}

@test "設定が無くても既定の 1900 で動く" {
  rm -f "$VOICE_LENGTH_CONF"
  seed first 100 '-1 hours'
  run_watch
  seed long 1950
  run_watch
  switches | grep -qF 'SWITCH: local'
}

@test "閾値が数値でなければ理由を示して止まる" {
  write_conf "たくさん"
  seed first 100
  run_watch
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -qF 'must be a positive integer'
  [ "$(switch_count)" -eq 0 ]
}

@test "閾値が 0 なら理由を示して止まる" {
  write_conf 0
  seed first 100
  run_watch
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -qF 'must be above 0'
  [ "$(switch_count)" -eq 0 ]
}

@test "DB が無ければ切り替えず終了する" {
  write_conf 1900
  run bash -c "TYPELESS_DB='$BATS_TEST_TMPDIR/missing.db' '$WATCH' 2>&1"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qF 'no Typeless database'
  [ "$(switch_count)" -eq 0 ]
}

@test "書き起こしが 1 件も無ければ何もしない" {
  write_conf 1900
  run_watch
  [ "$status" -eq 0 ]
  [ "$(switch_count)" -eq 0 ]
}

@test "LaunchAgent は 5 分間隔で voice-length-watch を起動する" {
  plist="$REPO_DIR/macos/local.voice-length-watch.plist"
  /usr/bin/plutil -lint "$plist" | grep -qF 'OK'
  /usr/libexec/PlistBuddy -c 'Print :StartInterval' "$plist" | grep -qF '300'
  /usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$plist" | grep -qF 'bin/voice-length-watch'
  /usr/libexec/PlistBuddy -c 'Print :Label' "$plist" | grep -qF 'local.voice-length-watch'
}

@test "setup が LaunchAgent の配置対象に入れている" {
  grep -qF 'local.voice-length-watch' "$REPO_DIR/setup/install.zsh"
}
