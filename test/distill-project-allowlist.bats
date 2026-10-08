#!/usr/bin/env bats
# distill-project は 対象.md に載ったリポジトリでだけ記録を書く。
#
# 判定は distill 本体に任せている。検査は SKILL.md の手順をそのまま取り出して
# 動かし、distill が「載っている」と読む書き方を一通り当てる。

load "helpers/common"

DISTILL_REPO="$HOME/develop/other/distill-of-ai-process"

setup() {
  make_tmpdir
  SK="$REPO_DIR/claude/skills/distill-project/SKILL.md"
  awk '/^\*\*対象\.md に載っていないリポジトリでは記録しない。\*\*/ { seen = 1; next }
       seen && /^```bash$/ { on = 1; next }
       on && /^```$/ { exit }
       on { print }' "$SK" >"$TEST_TMPDIR/check.sh"
  VAULT="$TEST_TMPDIR/vault"
  mkdir -p "$VAULT"
  FAKE_HOME="$TEST_TMPDIR/home"
  mkdir -p "$FAKE_HOME/develop/other"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

need_distill() {
  [ -x "$DISTILL_REPO/.venv/bin/python" ] || skip "distill が無い環境"
  ln -s "$DISTILL_REPO" "$FAKE_HOME/develop/other/distill-of-ai-process"
}

run_check() {
  run env HOME="$FAKE_HOME" VAULT="$VAULT" REPO="$2" \
    "$1" -c ". '$TEST_TMPDIR/check.sh'; echo CONTINUED"
}

# assert_goes_on <shell> <repo> <対象.md body>
assert_goes_on() {
  printf '%b' "$3" >"$VAULT/対象.md"
  run_check "$1" "$2"
  printf '%s\n' "$output" | grep -qF CONTINUED ||
    { echo "stopped for [$3] under $1: $output"; return 1; }
}

# assert_stops <shell> <repo> <対象.md body>
assert_stops() {
  printf '%b' "$3" >"$VAULT/対象.md"
  run_check "$1" "$2"
  n=$(printf '%s\n' "$output" | grep -c CONTINUED) || n=0
  [ "$n" -eq 0 ] || { echo "went on for [$3] under $1: $output"; return 1; }
  printf '%s\n' "$output" | grep -qF "記録しない: $2"
}

shells() {
  echo bash
  command -v zsh >/dev/null 2>&1 && echo zsh
}

@test "手順を SKILL.md から取り出せる" {
  grep -qF 'allowlist' "$TEST_TMPDIR/check.sh"
}

@test "distill が載っていると読む書き方なら記録する" {
  need_distill
  for sh in $(shells); do
    assert_goes_on "$sh" dxp '## プロジェクト\n- dxp\n'
    assert_goes_on "$sh" dxp '## リポジトリ\n- dxp\n'
    assert_goes_on "$sh" dxp '## Projects\n- dxp\n'
    assert_goes_on "$sh" dxp '## <font color="#81A1C1">プロジェクト</font>\n- dxp\n'
    assert_goes_on "$sh" dxp '## プロジェクト\n* dxp\n'
    assert_goes_on "$sh" dxp '## プロジェクト\n- [[dxp|表示]]\n'
    assert_goes_on "$sh" dxp '## プロジェクト\n- dxp/\n'
    assert_goes_on "$sh" dxp '## プロジェクト\n- dxp.md\n'
    assert_goes_on "$sh" dxp '## プロジェクト\n- dxp  <!-- 仕事 -->\n'
  done
}

@test "載っていなければ記録しない" {
  need_distill
  for sh in $(shells); do
    assert_stops "$sh" dotfiles '## プロジェクト\n- dxp\n'
    assert_stops "$sh" dx '## プロジェクト\n- dxp\n'
    assert_stops "$sh" dxp '- dxp\n\n## プロジェクト\n- other\n'
    assert_stops "$sh" dxp '## プロジェクト\n- other\n\n## 書き方\n- dxp\n'
  done
}

@test "対象.md が無い・空なら記録しない" {
  need_distill
  for sh in $(shells); do
    rm -f "$VAULT/対象.md"
    run_check "$sh" dxp
    n=$(printf '%s\n' "$output" | grep -c CONTINUED) || n=0
    [ "$n" -eq 0 ] || { echo "no list, went on under $sh: $output"; return 1; }
    assert_stops "$sh" dxp '## プロジェクト\n'
  done
}

@test "手順 1 の変数が無ければ素通りせずに止まる" {
  for sh in $(shells); do
    printf '## プロジェクト\n- dxp\n' >"$VAULT/対象.md"
    run env -u VAULT HOME="$FAKE_HOME" REPO=dxp \
      "$sh" -c "( . '$TEST_TMPDIR/check.sh'; echo CONTINUED ) || echo STOPPED"
    n=$(printf '%s\n' "$output" | grep -c CONTINUED) || n=0
    [ "$n" -eq 0 ] || { echo "VAULT unset, went on under $sh: $output"; return 1; }
    printf '%s\n' "$output" | grep -qF 'VAULT:'
  done
}

@test "distill を読めなければ記録しない" {
  for sh in $(shells); do
    printf '## プロジェクト\n- dxp\n' >"$VAULT/対象.md"
    run_check "$sh" dxp
    n=$(printf '%s\n' "$output" | grep -c CONTINUED) || n=0
    [ "$n" -eq 0 ] || { echo "no distill, went on under $sh: $output"; return 1; }
    printf '%s\n' "$output" | grep -qF '判定できなかった'
  done
}
