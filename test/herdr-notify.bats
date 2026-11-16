#!/usr/bin/env bats
# 通知音とポップアップの切り替え。設定ファイルの複製と herdr のスタブで検査する。

load "helpers/common"

setup() {
  make_tmpdir
  cp "$BATS_TEST_DIRNAME/../terminal/herdr/config.toml" "$TEST_TMPDIR/real.toml"
  ln -s "$TEST_TMPDIR/real.toml" "$TEST_TMPDIR/config.toml"
  export HERDR_NOTIFY_CONFIG="$TEST_TMPDIR/config.toml"
  printf '#!/bin/bash\necho "$*" >> "%s/calls"\n' "$TEST_TMPDIR" > "$TEST_TMPDIR/herdr"
  chmod +x "$TEST_TMPDIR/herdr"
  export HERDR_BIN="$TEST_TMPDIR/herdr"
  CMD="$BATS_TEST_DIRNAME/../bin/herdr-notify"
}

teardown() { rm -rf "$TEST_TMPDIR"; }

@test "既定は音なし・macOS バナー" {
  run "$CMD"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'sound: off\npopup: system')" ]
}

@test "sound on で音が鳴る設定になりサーバーを再読み込みする" {
  run "$CMD" sound on
  [ "$status" -eq 0 ]
  run "$CMD"
  echo "$output" | grep -qFx "sound: on"
  grep -qFx "server reload-config" "$TEST_TMPDIR/calls"
}

@test "popup herdr に切り替えても他の設定は変わらない" {
  run "$CMD" popup herdr
  [ "$status" -eq 0 ]
  [ "$(grep -c '^delivery = "herdr"$' "$TEST_TMPDIR/real.toml")" -eq 1 ]
  [ "$(grep -c '^position = "top-right"$' "$TEST_TMPDIR/real.toml")" -eq 1 ]
  [ "$(grep -c '^enabled = false$' "$TEST_TMPDIR/real.toml")" -eq 1 ]
}

@test "symlink を壊さずに書き込む" {
  run "$CMD" popup off
  [ "$status" -eq 0 ]
  [ -L "$TEST_TMPDIR/config.toml" ]
}

@test "不正な値は拒否し設定を変えない" {
  cp "$TEST_TMPDIR/real.toml" "$TEST_TMPDIR/before"
  run "$CMD" popup loud
  [ "$status" -eq 2 ]
  [ "$(cmp -s "$TEST_TMPDIR/before" "$TEST_TMPDIR/real.toml"; echo $?)" -eq 0 ]
  [ ! -e "$TEST_TMPDIR/calls" ]
}
