#!/usr/bin/env bats
# claude/settings.json のインラインフック配線テスト。
# stdin JSON を渡して post-commit トリガと破壊的コマンドブロックの実挙動を見る。

load "helpers/common"

SETTINGS="${BATS_TEST_DIRNAME}/../claude/settings.json"

# Selected by matcher/content, not index, so reordering settings.json is safe.
post_cmd() {
  jq -r '.hooks.PostToolUse[] | select(.matcher=="Bash") | .hooks[].command
         | select(contains("post-commit"))' "$SETTINGS"
}

block_cmd() {
  jq -r '.hooks.PreToolUse[] | select(.matcher=="Bash") | .hooks[].command
         | select(contains("BLOCK"))' "$SETTINGS"
}

setup() {
  make_tmpdir
  mkdir -p "$TEST_TMPDIR/.claude/hooks"
  printf '#!/bin/bash\necho CALLED\n' > "$TEST_TMPDIR/.claude/hooks/post-commit.sh"
  chmod +x "$TEST_TMPDIR/.claude/hooks/post-commit.sh"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

# Runs the trigger against a stubbed post-commit.sh under a throwaway HOME.
run_post() {  # $1=stdin payload
  printf '%s' "$1" | HOME="$TEST_TMPDIR" bash -c "$(post_cmd)" 2>&1
}

run_block() {  # $1=stdin payload -> echo exit code
  printf '%s' "$1" | bash -c "$(block_cmd)" >/dev/null 2>&1
  echo $?
}

@test "post-commit trigger exists in settings" {
  run post_cmd
  [ -n "$output" ]
}

@test "destructive block exists in settings" {
  run block_cmd
  [ -n "$output" ]
}

@test "git commit triggers post-commit hook" {
  run run_post '{"tool_input":{"command":"git commit -m test"}}'
  printf '%s' "$output" | grep -qF "CALLED"
}

@test "non-commit command does not trigger" {
  run run_post '{"tool_input":{"command":"ls -la"}}'
  [ "$output" = "" ]
}

@test "broken JSON does not trigger" {
  run run_post 'not-json'
  [ "$output" = "" ]
}

@test "blocks rm -rf /" {
  run run_block '{"tool_input":{"command":"rm -rf /"}}'
  [ "$output" = "2" ]
}

@test "blocks rm -rf ~" {
  run run_block '{"tool_input":{"command":"rm -rf ~"}}'
  [ "$output" = "2" ]
}

@test "blocks rm -rf /usr" {
  run run_block '{"tool_input":{"command":"rm -rf /usr"}}'
  [ "$output" = "2" ]
}

@test "blocks rm -rf /etc subtree" {
  run run_block '{"tool_input":{"command":"rm -rf /etc/hosts"}}'
  [ "$output" = "2" ]
}

@test "blocks dd if=" {
  run run_block '{"tool_input":{"command":"dd if=/dev/zero of=/dev/sda"}}'
  [ "$output" = "2" ]
}

@test "allows normal command" {
  run run_block '{"tool_input":{"command":"ls -la /usr"}}'
  [ "$output" = "0" ]
}

@test "allows rm -rf of tmp path" {
  run run_block '{"tool_input":{"command":"rm -rf /tmp/foo"}}'
  [ "$output" = "0" ]
}

@test "allows rm -rf of home subdir" {
  run run_block '{"tool_input":{"command":"rm -rf ~/scratch/foo"}}'
  [ "$output" = "0" ]
}

@test "fail-open on empty stdin" {
  run run_block ''
  [ "$output" = "0" ]
}

# settings.json が名指しするフックは、この機械にあるだけでは足りない。追跡されて
# いなければ、別の機械では実体の無いスクリプトを叩きに行く。ファイルの存在では
# なく git の追跡を見るのは、そのため（手元にあるかは他機での動作を保証しない）。
@test "settings が名指しするフックはすべてリポジトリに入っている" {
  run python3 -c "
import json, re, subprocess
d = json.load(open('$REPO_DIR/claude/settings.json'))
cmds = []
for arr in (d.get('hooks') or {}).values():
    for g in arr:
        for h in g.get('hooks', []):
            cmds.append(h.get('command', ''))
names = set()
for c in cmds:
    names |= set(re.findall(r'\.claude/hooks/([A-Za-z0-9._-]+)', c))
tracked = set(subprocess.run(
    ['git', '-C', '$REPO_DIR', 'ls-files', 'claude/hooks'],
    capture_output=True, text=True).stdout.split())
missing = sorted(n for n in names if f'claude/hooks/{n}' not in tracked)
print(','.join(missing) if missing else f'OK ({len(names)} 件)')
"
  [ "$status" -eq 0 ]
  case "$output" in OK*) : ;; *) echo "未追跡: $output"; return 1 ;; esac
}

# --- deploy-guard: 本番 Lambda デプロイの遮断 ---
#
# 塞ぐのは Claude のツール経路だけで、人が GitHub Actions の画面から実行する経路は
# 妨げない。「止まること」より「止めすぎないこと」のほうが壊れやすいので、通す側も
# 同じだけ検査する。
#
# 遮断語は変数に組み立てて渡す。このファイルを Bash 経由で書くと、コマンド文字列に
# 含まれた遮断語をガード自身が検出して編集ごと止める。
guard() {  # $1 = command -> exit code
  local json
  json=$(python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.argv[1]}}))' "$1")
  printf '%s' "$json" | sh "$REPO_DIR/claude/hooks/deploy-guard.sh" >/dev/null 2>&1
  echo $?
}

@test "deploy-guard: Lambda の直接更新を止める" {
  local verb="update-function"
  [ "$(guard "aws lambda ${verb}-code --function-name x")" -eq 2 ]
  # 環境変数の前置きがあっても素通りさせない
  [ "$(guard "AWS_PROFILE=p aws lambda ${verb}-configuration --function-name x")" -eq 2 ]
}

@test "deploy-guard: ワークフローの API 起動を止める" {
  [ "$(guard 'gh workflow run deploy.yml')" -eq 2 ]
  [ "$(guard 'curl -X POST https://api.github.com/repos/o/r/actions/workflows/d.yml/dispatches')" -eq 2 ]
}

@test "deploy-guard: 梱包のみは通す（止めすぎない）" {
  [ "$(guard './deploy-tou-report-lambdas.sh --environment dev --package-only')" -eq 0 ]
}

@test "deploy-guard: 実アップロードは止める" {
  [ "$(guard './deploy-tou-report-lambdas.sh --environment prod')" -eq 2 ]
}

@test "deploy-guard: 読み取りと無関係な操作は通す" {
  [ "$(guard 'cat deploy-tou-report-lambdas.sh')" -eq 0 ]
  # workflow_dispatch は YAML 編集で正当に現れるので、語だけでは止めない
  [ "$(guard 'grep workflow_dispatch .github/workflows/deploy.yml')" -eq 0 ]
  [ "$(guard 'aws lambda list-functions')" -eq 0 ]
  [ "$(guard 'ls')" -eq 0 ]
}

@test "deploy-guard: 入力が壊れていても通す（fail-open）" {
  # 遮断は多層防御の一枚であって境界ではない。ここで落ちると通常操作が全部止まる。
  n=$(printf 'not json' | sh "$REPO_DIR/claude/hooks/deploy-guard.sh" >/dev/null 2>&1; echo $?)
  [ "$n" -eq 0 ]
  n=$(printf '' | sh "$REPO_DIR/claude/hooks/deploy-guard.sh" >/dev/null 2>&1; echo $?)
  [ "$n" -eq 0 ]
}
