#!/usr/bin/env bats
# distill の記事の共通の書き方の規則と、それを参照する書き手。
load "helpers/common"

setup() {
  W="$REPO_DIR/claude/skills/_shared/references/distill-writing.md"
  DP="$REPO_DIR/claude/skills/distill-project/SKILL.md"
}

@test "共通の規則に 8 つの規則の見出しがある" {
  for h in "## 1. 用語" "## 2. 冒頭" "## 3. 文と表" "## 4. 見出し" "## 5. 重複" "## 6. 文体" "## 7. 読者向けでない情報" "## 8. 保存前の点検"; do
    grep -qF "$h" "$W"
  done
}

@test "共通の規則に読者像の線引きがある" {
  grep -qF '中堅のエンジニア' "$W"
  grep -qF '迷う語は注釈する' "$W"
  grep -qF '10〜25 字' "$W"
  grep -qF '80 字' "$W"
}

@test "distill-project は共通の規則を参照し、食い違う規則を残さない" {
  grep -qF '_shared/references/distill-writing.md' "$DP"
  ! grep -qF '本文に定義文を置かない' "$DP"
  ! grep -qF 'プログラミング経験の浅い初学者' "$DP"
  grep -qF '結論 → なぜ → 何を → どうやって' "$DP"
}

@test "distill-project の保存前の点検が読みやすさを数える" {
  grep -qF '未定義の語' "$DP"
  grep -qF '80 字を超える文' "$DP"
  grep -qF '2 節以上に重なる判断' "$DP"
}

@test "情報収集のダイジェストは共通の規則を参照し、です・ます で書く" {
  GL="$REPO_DIR/claude/skills/distill-gain-latest-info/SKILL.md"
  grep -qF '_shared/references/distill-writing.md' "$GL"
  grep -qF 'です・ます' "$GL"
}

@test "情報収集の Jev の採点の有無は本文ではなく改善提案に書く" {
  GL="$REPO_DIR/claude/skills/distill-gain-latest-info/SKILL.md"
  ! grep -qF '`## 深掘り` の見出しの直後に「Jev 未設定（採点なし）」' "$GL"
  grep -qF '`## 改善提案` に「Jev 未設定（採点なし）」' "$GL"
}

@test "情報収集の今日の要点は鍵の用語に一言注釈を付ける" {
  GL="$REPO_DIR/claude/skills/distill-gain-latest-info/SKILL.md"
  grep -qF '今日の要点** の各行は、鍵の用語に一言注釈を付ける' "$GL"
}
