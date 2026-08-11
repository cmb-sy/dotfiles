#!/usr/bin/env bats
# claude/settings.json の deny リストのテスト。
# CLAUDE.md「自律実行ワークフロー」節の禁止事項が、散文の約束ではなく
# 機械的な拒否として表現されていることを検査する。
#
# deny の照合は前方一致であり、コマンド全体の意味を見ない。つまり deny は
# 「正規の書き方を止める多層防御」であって境界ではない。前方一致ゆえに:
#   - 引数の後にフラグが来る形は外れる (git push origin main --force)
#   - サブコマンド前のグローバル option も外れる (git -C <path> reset --hard)
#   - フラグの並び替えも外れる (git clean -xfd)
#   - 逆に安全な --force-with-lease は --force に前方一致して止まる
# 逆向きの危険もある。エントリを広く書くと正当な操作を巻き込む。
# `rm -rf /` をここに置かないのはそのため: 前方一致で /private/tmp 等への
# 絶対パス削除まで全部止まる一方、本来止めたい `rm -rf /` 単体は同ファイルの
# PreToolUse フックが行末アンカー付きの正規表現で既に拒否している。

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

@test "privileged deletion is denied" {
  run deny_list
  printf '%s\n' "$output" | grep -qF 'sudo rm'
}

# `rm -rf /` belongs to the hook, not to deny: deny's prefix matching would take
# every absolute path with it, and the hook anchors the slash at end of string.
@test "root-level deletion is blocked by the hook" {
  run jq -r '.hooks.PreToolUse[].hooks[].command' "$SETTINGS"
  printf '%s\n' "$output" | grep -qF 'rm[[:space:]]+-rf'
}

@test "secret managers stay denied" {
  run deny_list
  printf '%s\n' "$output" | grep -qF 'sops'
  printf '%s\n' "$output" | grep -qF 'op:'
}

# Every prohibition CLAUDE.md's 自律実行ワークフロー section names must have an
# entry. A count check would pass on any four unrelated additions.
@test "each named prohibition has a deny entry" {
  run deny_list
  for needle in 'git push --force' 'git push -f' 'git reset --hard' 'git clean -fdx' 'sudo rm'; do
    printf '%s\n' "$output" | grep -qF "$needle"
  done
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

# The checks above look for exact entries, so they cannot see an entry that is a
# prefix of a legitimate command. Match the way deny actually matches instead.
@test "no deny entry prefix-matches a legitimate command" {
  legit='rm -rf /private/tmp/scratch
rm -rf /Users/x/build
git push origin main
git reset --soft HEAD~1
git clean -n
git stash list'
  denied=0
  while IFS= read -r cmd; do
    while IFS= read -r pattern; do
      # Bash(<prefix>:*) -> <prefix>
      prefix=${pattern#Bash(}
      prefix=${prefix%:\*)}
      case "$cmd" in
        "$prefix"*) echo "DENIED: '$cmd' by '$pattern'"; denied=$((denied + 1)) ;;
      esac
    done <<EOF
$(deny_list)
EOF
  done <<EOF
$legit
EOF
  [ "$denied" -eq 0 ]
}

@test "every deny entry is a scoped Bash pattern" {
  run deny_list
  [ "$status" -eq 0 ]
  # Anything not shaped `Bash(<cmd>:*)` would be a typo silently denying nothing.
  bad=$(printf '%s\n' "$output" | grep -cvE '^Bash\(.+:\*\)$' || true)
  [ "$bad" -eq 0 ]
}
