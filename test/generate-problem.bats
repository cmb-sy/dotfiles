#!/usr/bin/env bats
# distill のテーマから問題を出すスキル（generate-problem）の仕様。
#
# 対話で動くスキルなので、挙動そのものは実際に出題して確かめる。ここでは
# 「守るべき規則が SKILL.md に書かれていること」と「壊れる書き方が無いこと」を
# 文面で固定する。

load "helpers/common"

setup() {
  SK="$REPO_DIR/claude/skills/generate-problem/SKILL.md"
}

@test "frontmatter に name と description がある" {
  grep -qF 'name: generate-problem' "$SK"
  grep -qF 'description:' "$SK"
}

@test "記録先は distill の正本の 問題集 である" {
  grep -qF '$HOME/develop/distill-vault/問題集/<テーマ>/<YYYY-MM-DD-HHMM>.md' "$SK"
}

@test "足りない項目だけを聞き、難易度は選ばせない" {
  grep -qF '足りない項目だけ' "$SK"
  grep -qF '難易度は選ばせない' "$SK"
}

@test "下読みをエージェントに任せ、素材表の形が決まっている" {
  grep -qF 'general-purpose' "$SK"
  for k in 'concept:' 'explanation:' 'misconception:' 'aspect:' 'era:' 'source:'; do
    grep -qF "$k" "$SK"
  done
}

@test "材料はテーマの md をすべて使う" {
  grep -qF '材料を**すべて**読' "$SK"
}

@test "除外されたプロジェクトに紐付く学習メモを材料から外す" {
  grep -qF '$HOME/develop/distill-vault/除外.md' "$SK"
  grep -qF '`## プロジェクト` 見出しの下の箇条書き' "$SK"
  grep -qF '末尾の `<!-- ... -->` は注釈なので取り除いて読む' "$SK"
  grep -qF '除外されたプロジェクトに frontmatter の `project:` で紐付く学習メモは材料から外す' "$SK"
}

@test "除外.md の 記録 に書かれた記録を材料から外す" {
  grep -qF '`## 記録` 見出しの下の箇条書き' "$SK"
  grep -qF '`## 記録` に書かれた記録のファイルは材料から外す' "$SK"
}

@test "問題数は 1〜20 で、範囲外なら聞き直す" {
  grep -qF '問題数は 1〜20。範囲外なら範囲を伝えて聞き直す' "$SK"
}

@test "問う素養と、AI の時代に人に要る観点が書かれている" {
  for a in '| 仕組み |' '| 判断 |' '| 壊れ方 |' '| 大局 |'; do grep -qF "$a" "$SK"; done
  for e in '問題の定義と要件' '設計の天秤' 'AI の出力の検証' '壊れ方と観測' 'データの意味と品質' '安全と統制'; do
    grep -qF "$e" "$SK"
  done
}

@test "AI の答えのどこが危ういかを問う問題を 1 問以上入れる" {
  grep -qF 'AI が出したこの設計（答え）のどこが危ういか' "$SK"
  grep -qF '1 問以上' "$SK"
}

@test "細かい実装やテクニックは問わない" {
  grep -qF '構文・API の名前・コマンドのオプション・設定値の暗記・特定ツールの操作手順' "$SK"
}

@test "全問の後にまとめて採点・解説し、AI の時代に要る理由を添える" {
  grep -qF '正解は見せずに次へ' "$SK"
  grep -qF 'なぜ AI の時代にこれを人が分かっている必要があるか' "$SK"
}

@test "記述式は合っている点と足りない点に分けて評価する" {
  grep -qF '合っている点' "$SK"
  grep -qF '足りない点' "$SK"
}

@test "記録に勤務先の名前と絶対パスを書かない" {
  grep -qF '勤務先の名前と社内の作りを書かない' "$SK"
  grep -qF '絶対パス（ホームディレクトリの実際のパス）を書かない' "$SK"
}

@test "途中でやめたら答えた分を記録し、中断と書く" {
  grep -qF 'status: 中断' "$SK"
  grep -qF '`count:` は実際に答えた問題数にし、`score:` の分母もそれにする' "$SK"
  grep -qF 'planned: <予定の問題数>' "$SK"
  grep -qF '1 問も答えていなければ記録を書かず' "$SK"
}

@test "観点が なし の問題は見出しに素養だけを書く" {
  grep -qF '`era` が「なし」の概念から作った問題は、見出しを `（<素養>）` だけにする' "$SK"
}

@test "記録の時刻は出題を始めた時刻で、同名があれば番号を足す" {
  grep -qF '`<YYYY-MM-DD-HHMM>` は出題を始めた時刻' "$SK"
  grep -qF '同名のファイルがあれば `-2`、`-3` と番号を足す' "$SK"
}

@test "SKILL.md に個人の絶対パスが無い" {
  [ -f "$SK" ]
  n=$(grep -c '/Users/' "$SK") || n=0
  [ "$n" -eq 0 ]
}
