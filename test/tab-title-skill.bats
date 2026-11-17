#!/usr/bin/env bats
# tab-title スキル（herdr タブを今の作業名にする）の仕様を文面で固定する。

load "helpers/common"

setup() {
  SK="$REPO_DIR/claude/skills/tab-title/SKILL.md"
  CM="$REPO_DIR/claude/CLAUDE.md"
}

@test "frontmatter に name: tab-title と description がある" {
  grep -qx 'name: tab-title' "$SK"
  grep -q '^description:' "$SK"
}

@test "番号はブランチから先に取る" {
  grep -qF 'ブランチ' "$SK"
}

@test "題は 10 文字以内" {
  grep -qF '10 文字' "$SK"
}

@test "herdr-tab-title で改名する" {
  grep -qF 'herdr-tab-title' "$SK"
}

@test "CLAUDE.md から tab-title skill を呼ぶ" {
  grep -qF 'tab-title skill' "$CM"
}
