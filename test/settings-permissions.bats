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

# Prefix matching does not see flags that are combined or reordered, so each
# spelling needs its own entry. Measured: `git push -qf` reached the remote with
# only --force and -f denied.
@test "force push is denied in every spelling deny can express" {
  run deny_list
  for spelling in 'git push --force' 'git push -f' 'git push -qf' 'git push -fq'; do
    printf '%s\n' "$output" | grep -qF "$spelling"
  done
}

# What deny still cannot reach, so nobody reads the list as a boundary: a flag
# placed after the refspec is not a prefix of anything here.
@test "フラグが後ろに来る形は deny では止まらない" {
  run deny_list
  denied=0
  while IFS= read -r pattern; do
    prefix=${pattern#Bash(}
    prefix=${prefix%:\*)}
    case 'git push origin main --force' in "$prefix"*) denied=1 ;; esac
  done <<EOF
$output
EOF
  [ "$denied" -eq 0 ]
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

# The prohibitions that a Bash pattern can express. CLAUDE.md also forbids
# production database operations and deleting secrets, which deny cannot state:
# the command shape does not reveal which database or which file. Those stay with
# the PreToolUse hook and with judgement. A count check would pass on any four
# unrelated additions, so name them.
@test "the deniable prohibitions each have an entry" {
  run deny_list
  for needle in 'git push --force' 'git push -f' 'git reset --hard' 'git clean -fdx' 'sudo rm'; do
    printf '%s\n' "$output" | grep -qF "$needle"
  done
}

# bypassPermissions は意図的な選択であり、事故ではない。自動セキュリティレビューが
# 定期的に「auto へ戻せ」と指摘するが、その提案のうち「broad な Bash(rm:*) 等を allow
# から外す」は本構成では無意味である。bypassPermissions では allow リスト自体が参照
# されないため、外してもリスクは変わらない。
#
# 実際に効いている防御は permission mode と独立に動く層のほう:
#   - pii-guard.py (PreToolUse: Write|Edit|Bash)
#   - 破壊的コマンドの PreToolUse ブロッカー (rm -rf の / ~ $HOME を行末アンカーで拒否)
#   - deny 11 件 (sops / op / ssh / scp / force push / reset --hard / clean -fdx / sudo rm)
#
# ただしこれらは前置一致と正規表現であって境界ではない。真の隔離境界が要るなら
# issue #8 (OCI 無料枠に inbound 全閉じの Claude 常駐サーバーを立てる) が答えで、
# 設計と実装は済んでおり実機構築だけが残っている。モードを変えるならそちらが先。
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

# 追跡された settings.json は全マシンで共有する設定であり、かつ symlink 経由で
# Claude Code のランタイムに書き換えられる。auto モードを有効にすると、ランタイムは
# 作業中リポジトリの棚卸し(組織名・private リポジトリ一覧・秘密情報の管理方式)を
# autoMode.environment に書き込む。dotfiles は公開リポジトリなので、それは公開される。
#
# autoMode はリポジトリ単位の状態なので、置き場は作業リポジトリ側の
# .claude/settings.local.json(プロジェクトレベル・gitignore 済み)。ユーザーレベルの
# settings.local.json は Claude Code が読まないため、退避先にはならない。
#
# 組織名を並べた grep にしないのは、その検査自体が公開リポジトリに組織名を書き足す
# ことになるため。構造で見れば、どの組織のどの名前が来ても止まる。
@test "autoMode は追跡された settings.json に現れない" {
  run jq -r 'has("autoMode")' "$SETTINGS"
  [ "$output" = "false" ]
}
