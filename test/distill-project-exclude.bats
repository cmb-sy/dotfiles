#!/usr/bin/env bats
# distill-project は 除外.md に載ったリポジトリで記録を書かない。
#
# 判定は distill 本体に任せている。distill と別の解釈で読むと、食い違った
# ぶんだけ書いた直後に purge で消える記録ができるので、検査は SKILL.md の
# 手順をそのまま取り出して動かし、distill が除外と読む書き方を一通り当てる。

load "helpers/common"

DISTILL_REPO="$HOME/develop/other/distill-of-ai-process"

setup() {
  make_tmpdir
  SK="$REPO_DIR/claude/skills/distill-project/SKILL.md"
  # The check as the skill runs it: the first bash block after its lead line.
  awk '/^\*\*除外されているリポジトリでは記録しない。\*\*/ { seen = 1; next }
       seen && /^```bash$/ { on = 1; next }
       on && /^```$/ { exit }
       on { print }' "$SK" >"$TEST_TMPDIR/check.sh"
  VAULT="$TEST_TMPDIR/vault"
  mkdir -p "$VAULT"
  # The block finds distill under $HOME, so give it a HOME we control.
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

# run_check <shell> <repo>: run the block, then say whether the skill went on.
run_check() {
  run env HOME="$FAKE_HOME" VAULT="$VAULT" REPO="$2" \
    "$1" -c ". '$TEST_TMPDIR/check.sh'; echo CONTINUED"
}

# assert_stops <shell> <repo> <除外.md body>
assert_stops() {
  printf '%b' "$3" >"$VAULT/除外.md"
  run_check "$1" "$2"
  n=$(printf '%s\n' "$output" | grep -c CONTINUED) || n=0
  [ "$n" -eq 0 ] || { echo "went on for [$3] under $1: $output"; return 1; }
  printf '%s\n' "$output" | grep -qF "記録しない: $2"
}

# assert_goes_on <shell> <repo> <除外.md body>
assert_goes_on() {
  printf '%b' "$3" >"$VAULT/除外.md"
  run_check "$1" "$2"
  printf '%s\n' "$output" | grep -qF CONTINUED ||
    { echo "stopped for [$3] under $1: $output"; return 1; }
}

shells() {
  echo bash
  command -v zsh >/dev/null 2>&1 && echo zsh
}

@test "手順を SKILL.md から取り出せる" {
  grep -qF 'has_project' "$TEST_TMPDIR/check.sh"
}

@test "distill が除外と読む書き方では記録しない" {
  need_distill
  for sh in $(shells); do
    assert_stops "$sh" cwd '## プロジェクト\n- cwd\n'
    assert_stops "$sh" cwd '## リポジトリ\n- cwd\n'
    assert_stops "$sh" cwd '## Projects\n- cwd\n'
    assert_stops "$sh" cwd '## projects\n- cwd\n'
    assert_stops "$sh" cwd '##\tプロジェクト\n- cwd\n'
    assert_stops "$sh" cwd '## <font color="#81A1C1">プロジェクト</font>\n- cwd\n'
    assert_stops "$sh" cwd '## プロジェクト\n* cwd\n'
    assert_stops "$sh" cwd '## プロジェクト\n  + cwd\n'
    assert_stops "$sh" cwd '## プロジェクト\n- [[cwd]]\n'
    assert_stops "$sh" cwd '## プロジェクト\n- [[cwd|使い捨て]]\n'
    assert_stops "$sh" cwd '## プロジェクト\n- cwd/\n'
    assert_stops "$sh" cwd '## プロジェクト\n- cwd.md\n'
    assert_stops "$sh" cwd '## プロジェクト\n- cwd  <!-- 検証用 -->\n'
  done
}

@test "見出し・注意書き・例示つきの一覧でも名指しされたものだけ止まる" {
  need_distill
  body='# 除外\n\n説明。\n\n## プロジェクト\n\n- cwd  <!-- 使い捨て -->\n- dotfiles  <!-- 手元の道具 -->\n\n## 記録\n\n<!-- 例: - dxp/2026-09-10-1550 -->\n\n---\n\n## 書き方\n\n- 見出しの下に置く\n'
  for sh in $(shells); do
    assert_stops "$sh" dotfiles "$body"
    assert_goes_on "$sh" dxp "$body"
  done
}

@test "プロジェクトとして名指しされていなければ記録する" {
  need_distill
  for sh in $(shells); do
    assert_goes_on "$sh" cwd '## 記録\n- cwd\n'
    assert_goes_on "$sh" cwd '- cwd\n\n## プロジェクト\n- obsidian\n'
    assert_goes_on "$sh" cwd '## メモ\n- cwd\n'
    assert_goes_on "$sh" cwd '## プロジェクト\n- obsidian\n\n## 書き方\n- cwd\n'
    assert_goes_on "$sh" cw '## プロジェクト\n- cwd\n'
    assert_goes_on "$sh" cwd-2 '## プロジェクト\n- cwd\n'
  done
}

@test "除外.md が無ければ黙って記録する" {
  need_distill
  for sh in $(shells); do
    rm -f "$VAULT/除外.md"
    run_check "$sh" cwd
    [ "$status" -eq 0 ]
    [ "$output" = CONTINUED ] || { echo "under $sh: $output"; return 1; }
  done
}

@test "手順 1 の変数が無ければ素通りせずに止まる" {
  # Run apart from step 1, the check would read no list and let every repo in.
  # The subshell reports the failed stop as STOPPED; bash exits 127 there, zsh 1.
  # Match the variable name, not the hint: zsh escapes non-ASCII under LC_ALL=C.
  for sh in $(shells); do
    printf '## プロジェクト\n- cwd\n' >"$VAULT/除外.md"
    run env -u VAULT HOME="$FAKE_HOME" REPO=cwd \
      "$sh" -c "( . '$TEST_TMPDIR/check.sh'; echo CONTINUED ) || echo STOPPED"
    n=$(printf '%s\n' "$output" | grep -c CONTINUED) || n=0
    [ "$n" -eq 0 ] || { echo "VAULT unset, went on under $sh: $output"; return 1; }
    printf '%s\n' "$output" | grep -qF STOPPED
    printf '%s\n' "$output" | grep -qF 'VAULT:'
    run env HOME="$FAKE_HOME" VAULT="$VAULT" REPO= \
      "$sh" -c "( . '$TEST_TMPDIR/check.sh'; echo CONTINUED ) || echo STOPPED"
    n=$(printf '%s\n' "$output" | grep -c CONTINUED) || n=0
    [ "$n" -eq 0 ] || { echo "REPO empty, went on under $sh: $output"; return 1; }
    printf '%s\n' "$output" | grep -qF STOPPED
  done
}

@test "distill を読めなければ知らせたうえで記録する" {
  # No distill under FAKE_HOME: the check must not block the record.
  for sh in $(shells); do
    printf '## プロジェクト\n- cwd\n' >"$VAULT/除外.md"
    run_check "$sh" cwd
    printf '%s\n' "$output" | grep -qF CONTINUED
    printf '%s\n' "$output" | grep -qF '判定できなかった'
  done
}
