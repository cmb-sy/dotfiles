#!/usr/bin/env bats
# autopilot スキル（承認 1 回で最後まで進める経路）の仕様を文面で固定する。

load "helpers/common"

setup() {
  SK="$REPO_DIR/claude/skills/autopilot/SKILL.md"
  CM="$REPO_DIR/claude/CLAUDE.md"
}

@test "frontmatter に name: autopilot と description がある" {
  grep -qx 'name: autopilot' "$SK"
  grep -q '^description:' "$SK"
}

@test "superpowers の 3 skill を呼ぶ" {
  grep -qF 'superpowers:brainstorming' "$SK"
  grep -qF 'superpowers:writing-plans' "$SK"
  grep -qF 'superpowers:subagent-driven-development' "$SK"
}

@test "計画に判断の表の見出し行がある" {
  grep -qxF '| 途中で出そうな判断 | 答え | 理由 |' "$SK"
}

@test "止まってよいのは 3 つ" {
  grep -qF '外向き操作' "$SK"
  grep -qF '戻せない操作' "$SK"
  grep -qF '計画の前提が崩れた' "$SK"
}

@test "報告の 4 節" {
  for h in '## やったこと' '## 確かめた証拠' '## 推奨で決めた判断' '## 研鑽'; do
    grep -qxF "$h" "$SK"
  done
}

@test "研鑽は 6 軸から 1〜2 個と問い 1 つ" {
  for k in '問題の定義' '設計の天秤' 'AI の出力の検証' '壊れ方と観測' 'データの意味' '安全と統制' '自分で確かめる問い'; do
    grep -qF "$k" "$SK"
  done
}

@test "承認は設計の 1 回" {
  grep -qF '承認は設計の 1 回' "$SK"
  grep -qF 'writing-plans の承認は取らない' "$SK"
}

@test "link は md-view で出す" {
  grep -qF '"$HOME/dotfiles/bin/md-view"' "$SK"
}

@test "git 管理外は info/exclude" {
  grep -qF '.git/info/exclude' "$SK"
  grep -qF 'git check-ignore' "$SK"
}

@test "研鑽の写し先と対象.md の確認" {
  grep -qF 'プロジェクト/<名前>/記録/<YYYY-MM-DD-HHMM>.md' "$SK"
  grep -qF '対象.md' "$SK"
  grep -qF 'distill-repo-name' "$SK"
}

@test "CLAUDE.md の経路表に任せきりがある" {
  grep -q '^| 任せきり' "$CM"
}

@test "CLAUDE.md の例外 2 つ" {
  grep -qF '報告 md の研鑽' "$CM"
  grep -qF '全文は link' "$CM"
}

@test "生成した html も git 管理外にする" {
  grep -qF 'docs/superpowers/**/*.html' "$SK"
}

@test "CLAUDE.md の Git Workflow に任せきり中の commit がある" {
  grep -qF '3 択なし' "$CM"
}

@test "任せきりの行はいきなり実装の行より前" {
  a=$(grep -n '^| 任せきり' "$CM" | cut -d: -f1)
  b=$(grep -n '^| \*\*いきなり実装' "$CM" | cut -d: -f1)
  [ -n "$a" ]
  [ "$a" -lt "$b" ]
}

@test "任せきりの行は設計の承認で始まる" {
  grep '^| 任せきり' "$CM" | grep -qF '設計を 1 回承認'
}
