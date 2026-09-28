#!/usr/bin/env bats
# bin/distill-repo-name のテスト。
#
# 記録をどのプロジェクトに書くかを決める。名前が揺れると、同じプロジェクトが
# サイト上で 2 つに割れる（名前を付け直したプロジェクト、worktree）。

load "helpers/common"

SCRIPT="${BATS_TEST_DIRNAME}/../bin/distill-repo-name"

setup() {
  make_tmpdir
  VAULT="$TEST_TMPDIR/vault"
  mkdir -p "$VAULT/プロジェクト"
  REPO="$TEST_TMPDIR/work/my-repo"
  mkdir -p "$(dirname "$REPO")"
  git init -q -b main "$REPO"
  git -C "$REPO" -c user.email="test@example.com" -c user.name="test" \
    commit -q --allow-empty -m "init"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

name_of() {
  DISTILL_VAULT="$VAULT" bash "$SCRIPT" "$1"
}

overview() {
  local project="$1" repo_line="$2"
  mkdir -p "$VAULT/プロジェクト/$project"
  printf -- '---\n%s\nsha: 0\n---\n# %s\n' "$repo_line" "$project" >"$VAULT/プロジェクト/$project/概要.md"
}

@test "distill-repo-name: 対応する概要が無ければリポジトリの名前" {
  [ "$(name_of "$REPO")" = "my-repo" ]
}

@test "distill-repo-name: 概要の repo: が origin と同じプロジェクトに寄せる" {
  # 人が名前を付け直したプロジェクト。ディレクトリ名では見つからない。
  # origin は ssh の形（ユーザー名つき、区切りが :）で、概要は https の形。
  local at="@"
  git -C "$REPO" remote add origin "git${at}github.com:Example/My-Repo.git"
  overview "付け直した名前" "repo: https://github.com/example/my-repo"
  overview "別のもの" "repo: https://github.com/example/other"
  [ "$(name_of "$REPO")" = "付け直した名前" ]
}

@test "distill-repo-name: 本文にある repo: の行には反応しない" {
  git -C "$REPO" remote add origin https://github.com/example/my-repo.git
  mkdir -p "$VAULT/プロジェクト/本文だけ"
  printf -- '# 本文だけ\n\nrepo: https://github.com/example/my-repo\n' >"$VAULT/プロジェクト/本文だけ/概要.md"
  [ "$(name_of "$REPO")" = "my-repo" ]
}

@test "distill-repo-name: worktree は元のリポジトリの名前" {
  git -C "$REPO" worktree add -q -b feature "$TEST_TMPDIR/work/my-repo-123"
  [ "$(name_of "$TEST_TMPDIR/work/my-repo-123")" = "my-repo" ]
  # サブディレクトリから聞いても同じ。
  mkdir -p "$TEST_TMPDIR/work/my-repo-123/sub"
  [ "$(name_of "$TEST_TMPDIR/work/my-repo-123/sub")" = "my-repo" ]
}

@test "distill-repo-name: worktree も概要の repo: があればそちらに寄せる" {
  git -C "$REPO" remote add origin https://github.com/example/my-repo.git
  git -C "$REPO" worktree add -q -b feature "$TEST_TMPDIR/work/my-repo-123"
  overview "寄せ先" "repo: https://github.com/example/my-repo"
  [ "$(name_of "$TEST_TMPDIR/work/my-repo-123")" = "寄せ先" ]
}

@test "distill-repo-name: git リポジトリの外では何も出さず 1 で抜ける" {
  mkdir -p "$TEST_TMPDIR/plain"
  run name_of "$TEST_TMPDIR/plain"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}
