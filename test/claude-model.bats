#!/usr/bin/env bats
# Claude Code の既定モデルの固定先。
#
# claude/settings.json の model キーはランタイムが所有する。`/model` を使うと
# 書き換わり、この machine の全セッションが symlink で同じファイルを読むため、
# どこか 1 つの切り替えが全体の既定を変える。だから固定先は環境変数であり、
# その宣言が消えていないことをここで検査する。
#
# 検査はコメントを除いた行に当てる。この節の説明文には両方の変数名が出てくる
# ので、素の grep では「書いてある」と誤判定する。

load "helpers/common"

# コメント行と行末コメントを落とした .zshrc
zshrc_code() {
  grep -v '^[[:space:]]*#' "$REPO_DIR/.zshrc" | sed 's/[[:space:]]#.*$//'
}

@test ".zshrc が既定モデルを環境変数で固定している" {
  zshrc_code | grep -qF 'export ANTHROPIC_MODEL='
}

@test "固定されているモデルは opus" {
  zshrc_code | grep -E '^export ANTHROPIC_MODEL=' | grep -qF 'opus'
}

@test "無視される変数名を使っていない" {
  # ANTHROPIC_DEFAULT_MODEL は読まれない。無効な値を入れても何も起きないので、
  # こちらに書き替えると「設定したのに効いていない」を無言で作る。
  n=$(zshrc_code | grep -c 'ANTHROPIC_DEFAULT_MODEL') || n=0
  [ "$n" -eq 0 ]
}

@test ".zshrc は zsh として構文が通る" {
  run zsh -n "$REPO_DIR/.zshrc"
  [ "$status" -eq 0 ]
}
