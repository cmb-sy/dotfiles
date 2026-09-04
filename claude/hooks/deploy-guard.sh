#!/bin/sh
# Lambda デプロイの実行を Claude のツール経路から遮断する。
#
# 人間が GitHub Actions の画面から手動実行する経路は一切妨げない。
# GitHub 側は UI のボタン押下と API 起動を区別できないため、API 経路
# （gh workflow run / .../dispatches）をここで塞ぐことでしか
# 「手動のみ」を担保できない。
#
# 終了コード 2 でツール実行がブロックされる。
set -u

cmd=$(jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -z "$cmd" ] && exit 0

block() {
  echo "BLOCK: $1 は Claude から実行できません。" >&2
  echo "デプロイは GitHub Actions の画面から手動で実行してください。" >&2
  echo "ローカルでの梱包検証は --package-only を使ってください。" >&2
  exit 2
}

# 1) AWS API による関数コード・設定の直接更新
#    環境変数の前置き（AWS_PROFILE=x aws ...）や cd との連結も文字列に含まれるため
#    サブコマンド名で判定する。
if echo "$cmd" | grep -qE 'update-function-code|update-function-configuration'; then
  block "Lambda 関数の更新"
fi

# 2) ワークフローの API 起動
#    workflow_dispatch という語自体は YAML 編集で正当に現れるため対象にしない。
if echo "$cmd" | grep -qE 'gh[[:space:]]+workflow[[:space:]]+run|/actions/workflows/[^[:space:]]*/dispatches'; then
  block "GitHub Actions ワークフローの API 起動"
fi

# 3) デプロイスクリプトの実アップロード
#    --environment は実行時のみ付く引数。cat / grep での読み取りは通す。
if echo "$cmd" | grep -q 'deploy-tou-report-lambdas\.sh' && echo "$cmd" | grep -q -- '--environment'; then
  if ! echo "$cmd" | grep -q -- '--package-only'; then
    block "デプロイスクリプトのアップロード実行"
  fi
fi

exit 0
