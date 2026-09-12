#!/usr/bin/env bats
# 情報収集スキルの仕様。
#
# 2 か月間 1 件も出力しなかった対象なので、検査は「書いてあること」ではなく
# 「壊れる書き方が残っていないこと」に当てる。説明文にも語が出るため、
# 検査はコメントを除いた本文に当てる。

load "helpers/common"

setup() {
  SK="$REPO_DIR/claude/skills/distill-gain-latest-info/SKILL.md"
}

@test "dry-run が残っていない" {
  # 抑止すべき対話をサブエージェント側に置かない設計にしたので、
  # このフラグは存在自体が設計と矛盾する。
  n=$(grep -c -- '--dry-run' "$SK") || n=0
  [ "$n" -eq 0 ]
}

@test "廃止した出力先への言及が残っていない" {
  n=$(grep -c 'peer-watch' "$SK") || n=0
  [ "$n" -eq 0 ]
  m=$(grep -cE '情報収集/(watch|research)/' "$SK") || m=0
  [ "$m" -eq 0 ]
}

@test "出力先が正本の 情報収集 の 1 ファイルである" {
  # 正本は Obsidian vault から distill-vault へ移した。パスを固定して
  # おかないと、移管のたびに書き先が黙って古い場所へ戻る。
  grep -qF 'distill-vault/情報収集/' "$SK"
  n=$(grep -c 'index\.md' "$SK") || n=0
  [ "$n" -eq 0 ]
}

@test "週内クールダウンを gain-state に委ねている" {
  grep -qF 'gain-state due' "$SK"
  grep -qF 'gain-state record' "$SK"
}

@test "ダイジェストの件数と深さが指定されている" {
  grep -qE '3〜5 ?件' "$SK"
  grep -qF '自分の環境で何が変わるか' "$SK"
}

@test "改善提案は提示までで、適用しないと明記されている" {
  grep -qF '## 改善提案' "$SK"
  grep -qF 'このスキル自身は適用しない' "$SK"
}

@test "sources.yaml を読む記述が残っている" {
  grep -qF 'sources.yaml' "$SK"
}

# --- eod 側の配線 ---
#
# 「必ず実行する」と「承認を取る」は、サブエージェントに丸投げしたままでは
# 両立しない。収集はサブエージェント、承認は eod 本体、という分離を検査する。

@test "eod のスキップ選択肢から情報収集が消えている" {
  f="$REPO_DIR/claude/skills/eod/SKILL.md"
  # Step 0 の選択肢は「`名前` — 説明をスキップ」の形。宣言の形に当てる。
  n=$(grep -cE '^ +[0-9]+\. `distill-gain-latest-info' "$f") || n=0
  [ "$n" -eq 0 ]
}

@test "eod が dry-run を渡していない" {
  f="$REPO_DIR/claude/skills/eod/SKILL.md"
  n=$(grep -c -- '--dry-run' "$f") || n=0
  [ "$n" -eq 0 ]
}

@test "eod に改善提案の承認ステップがある" {
  f="$REPO_DIR/claude/skills/eod/SKILL.md"
  grep -qF '### Step 1.5' "$f"
  grep -qF '## 改善提案' "$f"
  grep -qF 'AskUserQuestion' "$f"
}

@test "eod が gain をサブエージェントに投げる記述は残っている" {
  f="$REPO_DIR/claude/skills/eod/SKILL.md"
  grep -qF 'distill-gain-latest-info' "$f"
}
