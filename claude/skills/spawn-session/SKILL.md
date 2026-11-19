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

## 4. issue に書き込み、デイリーに入れるか尋ねる

起動を確かめたら `AskUserQuestion` を 1 回呼ぶ（header: `デイリー`）。質問は「このタスク（<タスク名>）を issue に書き込み、今日のデイリーのフルサクセスに入れますか？」。選択肢:

1. issue に書き込んでデイリーに入れる
2. デイリーにだけ入れる
3. どちらもしない

### 4a. issue に書き込む（1 のとき）

AITF の木は「テーマ（`【FY26下期】…`、親なし）→ エピック（`【データ基盤】…` など）→ 目標 issue」の **3 段まで**。4 段目は作らない。引き継いだ作業は、当てはまる目標 issue の本文に**タスクとして書き込む**。新しい issue は作らない。

1. 書き込む目標 issue を選ぶ。目標 issue は Obsidian の `02_quant/目標設定/FY26下期.md` のプロセス目標と 1 対 1 に対応する。テーマから 2 段下を読み、目標設定の文と照らして候補にする:

   ```bash
   gh api graphql -f query='{repository(owner:"Resily",name:"<テーマの repo>"){issue(number:<テーマ>){subIssues(first:20){nodes{number title subIssues(first:30){nodes{number title state repository{name}}}}}}}}' \
     --jq '.data.repository.issue.subIssues.nodes[]|.number as $e|.title as $et|.subIssues.nodes[]|select(.state=="OPEN")|"\(.repository.name)#\(.number)\t\($et)\t\(.title)"'
   ```

   テーマは AITF ボードで親なし・`【FY26下期】` の issue（データ基盤なら data-platform#275）。一番近い目標 issue を推奨にし、次点 1〜2 件と並べて `AskUserQuestion`（header: `issue`）で選んでもらう
2. 本文を読み（`gh issue view <番号> --repo Resily/<repo> --json body --jq .body`）、追記の草案を作る。既存の文は変えず、末尾に節を足す:

   ```markdown
   ## タスク
   - [ ] <やること>（期限 M/D）
   ```

   `## タスク` の節がすでにあれば、その末尾に行を足す。同じ内容の行は重ねない。1 行 1 タスクで、結果が分かる言い方にする。背景や仕様の表は書かず、引き継ぎ文書に残す。人名は書かず役割で書く
3. 草案（足す行だけ）を見せて止まる。**書き込みは合図を受けてから**（外向き操作）
4. 書き込む。本文全体を一時ファイルに書いて `gh issue edit <番号> --repo Resily/<repo> --body-file <ファイル>`。書いた後に本文を読み直し、元の文が残っていることを確かめる
5. 合う目標 issue が無いときだけ、エピックの下に新しい目標 issue を作るかをユーザーに尋ねる（作るなら `gh issue create` → AITF ボード project 26 に追加 → `addSubIssue` でエピックに付ける。草案を見せて合図を待つ）

### 4b. デイリーに入れる（1・2 のとき）

今日のデイリーの `### フルサクセス` の末尾（次の `### ` 見出しの直前）に 1 行足す。

- ファイル: `$HOME/develop/obsidian/01_daily/{YYYY}年/{M}月/{D}日({曜}).md`（月・日はゼロ埋めなし。`date` で今日の日付と曜日を取る）
- 行: `- [ ] <タスク名>`。タスク名はタブ名から番号を除いた題を基本に、何をする行か分かる言い方にする（例: `効果検証白書の集計要素の実現可能性を確認`）。4a で issue に書き込んだら、末尾に ` #<番号>` を付ける
- 同じ文言の行がすでにあれば足さない
- ファイルか見出しが無ければ足さずに、その旨を報告に書く
- vault の commit はしない（eod が締めでまとめて commit する）

## 5. 報告

タブ名・ペイン id・引き継ぎ文書の絶対パス、書き込んだ issue の URL、デイリーに足したかどうかを書く。
