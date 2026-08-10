#!/usr/bin/env bats
# claude/settings.json の deny リストのテスト。
# CLAUDE.md「自律実行ワークフロー」節の禁止事項が、散文の約束ではなく
# 機械的な拒否として表現されていることを検査する。

load "helpers/common"

SETTINGS="${BATS_TEST_DIRNAME}/../claude/settings.json"

deny_list() {
  jq -r '.permissions.deny[]' "$SETTINGS"
}

# Counts exact-line matches without tripping `set -e` when there are none.
deny_count_exact() {  # $1=entry
  deny_list | grep -cxF "$1" || true
}

@test "settings.json is valid JSON" {
  run jq empty "$SETTINGS"
  [ "$status" -eq 0 ]
}

@test "force push is denied in both flag spellings" {
  run deny_list
  printf '%s\n' "$output" | grep -qF 'git push --force'
  printf '%s\n' "$output" | grep -qF 'git push -f'
}

@test "destructive git history rewrites are denied" {
  run deny_list
  printf '%s\n' "$output" | grep -qF 'git reset --hard'
}

@test "destructive worktree wipes are denied" {
  run deny_list
  printf '%s\n' "$output" | grep -qF 'git clean -fdx'
}

@test "privileged and root-level deletion is denied" {
  run deny_list
  printf '%s\n' "$output" | grep -qF 'sudo rm'
  printf '%s\n' "$output" | grep -qF 'rm -rf /'
}

@test "secret managers stay denied" {
  run deny_list
  printf '%s\n' "$output" | grep -qF 'sops'
  printf '%s\n' "$output" | grep -qF 'op:'
}

@test "deny list has grown beyond the original four" {
  count=$(jq '.permissions.deny | length' "$SETTINGS")
  [ "$count" -gt 4 ]
}

@test "bypassPermissions is still the default mode" {
  run jq -r '.permissions.defaultMode' "$SETTINGS"
  [ "$output" = "bypassPermissions" ]
}

# deny は前方一致なので、動詞だけの広いパターンは日常操作を止めてしまう。
@test "no deny entry blocks a bare git verb" {
  [ "$(deny_count_exact 'Bash(git push:*)')" -eq 0 ]
  [ "$(deny_count_exact 'Bash(git reset:*)')" -eq 0 ]
  [ "$(deny_count_exact 'Bash(git clean:*)')" -eq 0 ]
  [ "$(deny_count_exact 'Bash(git:*)')" -eq 0 ]
}

@test "no deny entry blocks rm outright" {
  [ "$(deny_count_exact 'Bash(rm:*)')" -eq 0 ]
  [ "$(deny_count_exact 'Bash(rm -rf:*)')" -eq 0 ]
}

@test "every deny entry is a scoped Bash pattern" {
  run deny_list
  [ "$status" -eq 0 ]
  # Anything not shaped `Bash(<cmd>:*)` would be a typo silently denying nothing.
  bad=$(printf '%s\n' "$output" | grep -cvE '^Bash\(.+:\*\)$' || true)
  [ "$bad" -eq 0 ]
}
