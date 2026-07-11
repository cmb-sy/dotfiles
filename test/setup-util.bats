#!/usr/bin/env bats
# Tests for util::link in setup/util.zsh (run via zsh -c).

UTIL="${BATS_TEST_DIRNAME}/../setup/util.zsh"

run_link() {  # $1=src $2=dst
  zsh -c "source '$UTIL'; util::link '$1' '$2'"
}

setup() {
  TMP="$(mktemp -d)"
  echo "real" > "$TMP/src.txt"
}

teardown() { rm -rf "$TMP"; }

@test "creates symlink when dst is absent" {
  run run_link "$TMP/src.txt" "$TMP/dst"
  [ "$status" -eq 0 ]
  [ "$(readlink "$TMP/dst")" = "$TMP/src.txt" ]
}

@test "replaces existing symlink even if broken or wrong" {
  ln -s /nonexistent "$TMP/dst"
  run run_link "$TMP/src.txt" "$TMP/dst"
  [ "$status" -eq 0 ]
  [ "$(readlink "$TMP/dst")" = "$TMP/src.txt" ]
}

@test "skips and warns when dst is a real file" {
  echo "precious" > "$TMP/dst"
  run run_link "$TMP/src.txt" "$TMP/dst"
  [ "$status" -eq 1 ]
  [ "$(cat "$TMP/dst")" = "precious" ]
  [[ "$output" == *"not a symlink"* ]]
}

@test "skips and warns when src does not exist" {
  run run_link "$TMP/no-such-src" "$TMP/dst"
  [ "$status" -eq 1 ]
  [ ! -e "$TMP/dst" ]
  [[ "$output" == *"source not found"* ]]
}
