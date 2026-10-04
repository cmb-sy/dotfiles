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
  grep -qF '末尾の `<!-- ... -->` は注釈なので取り除き' "$SK"
  grep -qF '`[[ ]]`、末尾の `.md` と `/` も外して読む' "$SK"
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
  for a in '| 仕組み | なぜ' '| 判断 | どの状況で' '| 壊れ方 | どこで' '| 大局 | 全体の'; do grep -qF "$a" "$SK"; done
  for e in '問題の定義と要件 | AI は' '設計の天秤 | どの制約' 'AI の出力の検証 | AI は' '壊れ方と観測 | 壊れた' 'データの意味と品質 | 数字' '安全と統制 | 誰が'; do
    grep -qF "| $e" "$SK"
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

@test "形式は聞かず、答えは必ず選択式で受ける" {
  grep -qF '形式は聞かない（すべて 4 択で出す）' "$SK"
  grep -qF '答えは必ず AskUserQuestion の選択式で受ける' "$SK"
  run grep -cF '記述式' "$SK"
  [ "$output" = "0" ]
}

@test "問題文は前提・状況・問いの順に書き、用語を初出で定義する" {
  grep -qF '**前提**' "$SK"
  grep -qF '**状況**' "$SK"
  grep -qF '**問い**' "$SK"
  grep -qF '用語は初出で一言定義する' "$SK"
  a=$(grep -n '^1\. \*\*前提\*\*' "$SK" | cut -d: -f1)
  b=$(grep -n '^2\. \*\*状況\*\*' "$SK" | cut -d: -f1)
  c=$(grep -n '^3\. \*\*問い\*\*' "$SK" | cut -d: -f1)
  [ -n "$a" ] && [ "$a" -lt "$b" ] && [ "$b" -lt "$c" ]
}

@test "Other の答えは記述として採点せず、出し直す" {
  grep -qF '記述の答えとして採点せず' "$SK"
}

@test "記録の雛形に選択肢と聞き返しの欄がある" {
  grep -qF -- '- A: <選択肢>' "$SK"
  grep -qF '<聞き返しがあれば' "$SK"
}

@test "聞き返されたら具体例で説明して同じ問題を出し直す" {
  grep -qF '具体例を使って説明し、同じ問題を出し直す' "$SK"
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

# --- テーマを選択肢で選ばせ、Web の情報で問題と解説を補強する ---

@test "最初にテーマを選択肢で聞く（学習メモ全体・分類・プロジェクト）" {
  grep -qF 'Q1「どこから出しますか？」' "$SK"
  grep -qF '| 学習メモ全体 | なし |' "$SK"
  grep -qF '| 学習メモの分類から選ぶ | Q2' "$SK"
  grep -qF '| プロジェクトから選ぶ | Q2' "$SK"
}

@test "学習メモ全体を選んだときの材料が決まっている" {
  grep -qF '| 学習メモ全体 | `学習メモ/**/*.md` |' "$SK"
}

@test "出題に使う概念を Web で調べ、読んで確かめたものだけを使う" {
  grep -qF '## Step 3.5: Web で補強する' "$SK"
  grep -qF 'WebSearch' "$SK"
  grep -qF 'WebFetch' "$SK"
  grep -qF '確かめられなかった情報は使わない' "$SK"
}

@test "問題の芯は distill の材料に置き、Web の情報は補強に使う" {
  grep -qF '問題の芯は distill の材料に置き' "$SK"
}

@test "解説と記録に Web の出典の URL を残す" {
  grep -qF '## 参照した Web の情報' "$SK"
}
