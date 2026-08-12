#!/usr/bin/env bats
# Typeless publishes no quota, so the watcher works off its dictation log plus a
# measured limit. These run against a stub database and a stub voice-switch:
# the real one quits and relaunches apps.

load "helpers/common"

setup() {
  WATCH="$REPO_DIR/bin/voice-quota-watch"
  export VOICE_QUOTA_STATE="$BATS_TEST_TMPDIR/state"
  export VOICE_QUOTA_CONF="$BATS_TEST_TMPDIR/quota.conf"
  export SQLITE_BIN=/usr/bin/sqlite3
  export VOICE_SWITCH_BIN="$BATS_TEST_TMPDIR/voice-switch"
  export OSASCRIPT_BIN=/usr/bin/true
  printf '#!/bin/bash\necho "SWITCH: $*" >> "%s/switches"\n' "$BATS_TEST_TMPDIR" > "$VOICE_SWITCH_BIN"
  chmod +x "$VOICE_SWITCH_BIN"
  DB="$BATS_TEST_TMPDIR/typeless.db"
  export HOME_DB="$DB"
}

# Minutes of usage placed inside the current week, in Typeless's own format.
seed_db() {  # $1 = minutes
  /usr/bin/sqlite3 "$DB" "CREATE TABLE history_v2 (id TEXT, duration REAL, created_at TEXT);"
  /usr/bin/sqlite3 "$DB" "INSERT INTO history_v2 VALUES ('x', $1 * 60.0, strftime('%Y-%m-%dT%H:%M:%SZ','now'));"
}

write_conf() {  # $1 = limit, $2 = reset day, $3 = margin
  printf 'TYPELESS_LIMIT_MIN=%s\nTYPELESS_RESET_DAY=%s\nTYPELESS_MARGIN_MIN=%s\n' "$1" "$2" "$3" > "$VOICE_QUOTA_CONF"
}

run_watch() {
  TYPELESS_DB="$DB" run bash -c "TYPELESS_DB='$DB' '$WATCH' 2>&1"
}

switches() {
  cat "$BATS_TEST_TMPDIR/switches" 2>/dev/null || true
}

@test "上限が未計測なら何もせず理由を言う" {
  seed_db 10
  write_conf "" "" 3
  run_watch
  printf '%s' "$output" | grep -qF 'not measured yet'
  count=$(switches | grep -c .) || count=0
  [ "$count" -eq 0 ]
}

@test "上限に届いていなければ切り替えない" {
  seed_db 10
  write_conf 50 mon 3
  run_watch
  count=$(switches | grep -c .) || count=0
  [ "$count" -eq 0 ]
}

@test "上限からマージンを引いた線を越えたら Handy へ切り替える" {
  seed_db 48
  write_conf 50 mon 3
  run_watch
  switches | grep -qF 'SWITCH: local'
}

@test "同じ週で二度は切り替えない" {
  seed_db 48
  write_conf 50 mon 3
  run_watch
  run_watch
  count=$(switches | grep -c 'SWITCH: local') || count=0
  [ "$count" -eq 1 ]
}

@test "週が変わったら Typeless へ戻す" {
  seed_db 1
  write_conf 50 mon 3
  # Last week's state: we took it away then, and usage is back under the line.
  printf '2000-01-03 exhausted\n' > "$VOICE_QUOTA_STATE"
  run_watch
  switches | grep -qF 'SWITCH: typeless'
}

@test "自分が切り替えたのでなければ勝手に戻さない" {
  seed_db 1
  write_conf 50 mon 3
  printf '2000-01-03 reset\n' > "$VOICE_QUOTA_STATE"
  run_watch
  count=$(switches | grep -c .) || count=0
  [ "$count" -eq 0 ]
}

@test "リセット曜日が不正なら止まる" {
  seed_db 10
  write_conf 50 friday 3
  run_watch
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -qF 'must be mon or sun'
}

@test "DB が無ければ切り替えず終了する" {
  write_conf 50 mon 3
  run_watch
  [ "$status" -eq 0 ]
  count=$(switches | grep -c .) || count=0
  [ "$count" -eq 0 ]
}
