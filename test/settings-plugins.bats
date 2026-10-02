#!/usr/bin/env bats
# claude/settings.json の enabledPlugins のテスト。
# どちらのアカウントにもインストールされておらず、マーケットプレイスも登録されて
# いない plugin を有効化リストに残さない。

load "helpers/common"

SETTINGS="${BATS_TEST_DIRNAME}/../claude/settings.json"

@test "enabledPlugins に未インストールの plugin が残っていない" {
  for p in \
    ast-grep@ast-grep-marketplace \
    compound-engineering@every-marketplace \
    database-design@claude-code-workflows \
    document-skills@anthropic-agent-skills \
    postgres-best-practices@supabase-agent-skills \
    quantitative-trading@claude-code-workflows \
    remote-control@claude-plugins-official \
    skill-creator@anthropic-agent-skills \
    ui-ux-pro-max@ui-ux-pro-max-skill; do
    n=$(jq -r '.enabledPlugins | keys[]' "$SETTINGS" | grep -cxF "$p") || n=0
    echo "still enabled: $p ($n)"
    [ "$n" -eq 0 ]
  done
}

@test "enabledPlugins の plugin はすべて既知のマーケットプレイスのもの" {
  n=$(jq -r '.enabledPlugins | keys[] | sub("^[^@]*@"; "")' "$SETTINGS" \
    | grep -cvxE 'claude-plugins-official|openai-codex|pm-skills|worktrunk') || n=0
  [ "$n" -eq 0 ]
}
