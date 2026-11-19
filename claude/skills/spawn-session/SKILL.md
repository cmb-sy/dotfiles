---
name: spawn-session
description: >-
  いまの会話で決まった作業を、同じ herdr のワークスペースに新しいタブを作って
  別の Claude セッション（clwa）に引き継ぎ、依頼させる。
  「新しいセッションで始めたい」「タブを作ってやらせて」「別タブに渡して」で使う。
---

# spawn-session

## 1. 引き継ぎ文書を書く

scratchpad に `handoff_<題>.md` を Write で書く。新しいセッションはこの文書しか知らないので、これだけで作業を始められるようにする。

入れるもの:

- 依頼: やることを番号つきで。期限・担当・完了の条件
- 決まっていること: 会議・会話で確定した仕様や判断。表にできるものは表にする
- 待ちの入力: 誰から何が届くのを待っているか
- 背景: 関係する issue 番号、資料、データの置き場所（絶対パス）
- 制約: 外向き操作は草案を出して止まる、など会話で効いていた規則

書かないもの: 会話の経緯、PII（人名に「担当:」などのラベルを付けると pii-guard が止める。「ユーザー本人の作業」のように書く）。

## 2. タブを作って起動する

```bash
"$HOME/dotfiles/bin/herdr-spawn-session" "<handoff の絶対パス>" "<タブ名>" "<作業ディレクトリ>"
```

- タブ名は tab-title と同じ形（`#<番号> <題>`、無ければ題だけ。20 字まで）
- 作業ディレクトリを省くと今のディレクトリ
- 出力は新しいペインの id

## 3. 起動を確かめる

```bash
sleep 8; herdr pane read <ペイン id> --lines 15
```

Claude の入力欄か作業中の表示が出ていれば起動済み。シェルのエラーなら、その出力を見せて止まる。

## 4. issue にしてデイリーに入れるか尋ねる

起動を確かめたら `AskUserQuestion` を 1 回呼ぶ（header: `デイリー`）。質問は「このタスク（<タスク名>）を issue にして、今日のデイリーのフルサクセスに入れますか？」。選択肢:

1. issue にしてデイリーに入れる
2. デイリーにだけ入れる
3. どちらもしない

### 4a. issue を作る（1 のとき）

1. 親の issue を決める。会話と引き継ぎ文書に出た issue から、エピック（`gh api graphql` で `subIssues` を読む）の子のうち作業が一番近いものを選ぶ。リポジトリは親と同じにする
2. 草案を出して止まる。題・本文（依頼・期限・待ちの入力・引き継ぎ文書の要約）・リポジトリ・親・Status（In progress）を見せる。**作成は合図を受けてから**（外向き操作）。本文に人名を書かず役割で書く
3. 作る。`--assignee` は付けない

   ```bash
   gh issue create --repo Resily/<repo> --title "<題>" --body-file <本文の md>
   ITEM=$(gh project item-add 26 --owner Resily --url <URL> --format json --jq .id)
   gh project item-edit --id "$ITEM" --project-id PVT_kwDOArEsis4BIUQA \
     --field-id PVTSSF_lADOArEsis4BIUQAzg4z98s --single-select-option-id 47fc9ee4   # In progress
   gh api graphql -f query='mutation($p:ID!,$c:ID!){addSubIssue(input:{issueId:$p,subIssueId:$c}){issue{number}}}' \
     -f p="$(gh issue view <親> --repo Resily/<repo> --json id --jq .id)" \
     -f c="$(gh issue view <URL> --json id --jq .id)"
   ```

4. 親が data-platform#275 の木の中なら、#275 の「現在の状況」は作り直しが要ると報告に書く（作り直しは頼まれてから）
5. 引き継ぎ文書と新しいタブに issue 番号を伝える（`herdr pane send-text` は使わず、報告に書いてユーザーに任せる）

### 4b. デイリーに入れる（1・2 のとき）

今日のデイリーの `### フルサクセス` の末尾（次の `### ` 見出しの直前）に 1 行足す。

- ファイル: `$HOME/develop/obsidian/01_daily/{YYYY}年/{M}月/{D}日({曜}).md`（月・日はゼロ埋めなし。`date` で今日の日付と曜日を取る）
- 行: `- [ ] <タスク名>`。タスク名はタブ名から番号を除いた題を基本に、何をする行か分かる言い方にする（例: `効果検証白書の集計要素の実現可能性を確認`）。4a で issue を作ったら `- [ ] 【AITF】<issue の題> #<番号>` にする（課題の行の形。夜の同期がタスクノートのリンクに付け替える）
- 同じ文言の行がすでにあれば足さない
- ファイルか見出しが無ければ足さずに、その旨を報告に書く
- vault の commit はしない（eod が締めでまとめて commit する）

## 5. 報告

タブ名・ペイン id・引き継ぎ文書の絶対パスと、デイリーに足したかどうかを書く。
