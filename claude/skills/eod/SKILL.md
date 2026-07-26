---
name: eod
description: >-
  1 日の作業を締めたいとき（終業時・日報作成時）に使うオーケストレータ。
  Slack+GitHub 収集 → open issue 確認 → 日報生成 → CloudLog 入力 → 振り返り → 北極星ロースト更新 → 翌日デイリー作成 → 翌日タスクの GitHub issue 紐付け → Obsidian vault commit/push を順次実行する。
  除外プロジェクト指定は本文の Options を参照。
argument-hint: "[--exclude <キーワード>...]"
user-invocable: true
---

その日の作業を1コマンドで締める。**Slack+GitHub収集 → github-issues（open issue 確認）→ daily-log → CloudLog入力 → generate-problem → 北極星ロースト更新 → 翌日デイリー作成 → 翌日タスク整理（未チェックの自動引き継ぎ＋新規の GitHub issue 紐付け）→ Obsidian vault commit/push** を順次実行する。

## Options

| Option | 効果 |
|--------|------|
| `--exclude <キーワード>...` | 日報生成の対象から除外するプロジェクトを追加する。下記デフォルトに **合算** される（デフォルトを置き換えない） |

デフォルトで `--exclude siori --exclude generate-video --exclude shindanshi --exclude microsoft-agent-hackathon --exclude kunstSite --exclude dotfiles` を適用する。

---

## 実行フロー

### Step 0: スキップ対象の対話確認（必須・最初に実施）

**起動直後・他のステップに着手する前に必ず実施する**。`AskUserQuestion` で multiSelect の質問を1問だけ提示し、ユーザーがスキップしたいステップを選択させる。

- 質問文: 「スキップ対象を確認させてください。どのステップを飛ばしますか?」
- header: `Skip対象`
- multiSelect: `true`
- 選択肢（順序固定。AskUserQuestion の最大 4 件制約に合わせる）:
  1. `Step 5: generate-problem` — 本日の振り返り(過去問形式)をスキップ
  2. `Step 4: CloudLog 自動入力` — Playwright での CloudLog 入力をスキップ(daily-log でのエントリ生成は実施)
  3. `Step 1: Slack 収集` — 本日の Slack 発言・関与スレッド取得をスキップ
  4. `Step 1: GitHub 収集` — 本日のコミット・PR・Issue 活動取得をスキップ

Step 3(daily-log 自体のスキップ) などその他のスキップは `Other` (自由記述) で受け付ける。ユーザーが何も選択しなかった場合は「全ステップ実行」とみなす。複数選択可。選択結果は実行フロー全体で参照する。

**重要**:
- `--skip-*` 系のフラグ引数は廃止。引数で渡されてもこの質問は省略しない
- 質問は1回だけ。Step 1 以降に進んでから「やっぱりスキップしたい」が出ても再質問せず、ユーザーが /eod を再実行する想定
- Step 3 がスキップされた場合は Step 4(CloudLog 入力) も自動的にスキップする(エントリ未生成のため)
- Step 1 Slack/GitHub 片方または両方がスキップされた場合、daily-log は走査したセッション情報のみで成果セクションを生成する(取得失敗とは区別し「スキップにより未取得」と完了報告に明記)

### Step 1: Slack + GitHub 情報収集（並列）

以降のステップで使い回すため、最初に一括取得する。Step 0 で「Step 1: Slack 収集」がスキップされた場合は Slack 取得を、「Step 1: GitHub 収集」がスキップされた場合は GitHub 取得を、それぞれスキップする(両方スキップなら Step 1 全体をスキップ)。

- **Slack**: 本日の自分の発言・関与したスレッドを取得する。**取得経路は以下の優先順で必ずチェックする**:
  1. **`claude.ai Slack` MCP（最優先）** — `mcp__claude_ai_Slack__slack_search_public_and_private` を使う。`query="from:<@U07KEPWQAQN> after:{YYYY-MM-DD前日} before:{YYYY-MM-DD翌日}"`（user_id は固定）。スレッド文脈が必要な場合は `slack_read_thread`、チャンネル履歴は `slack_read_channel`
  2. **`slackcli` CLI（フォールバック）** — MCP が ToolSearch にも `claude mcp list` にも出ない場合のみ
  - **重要**: MCP ツールはセッション開始時の ToolSearch で必ず存在確認する。ToolSearch クエリ `slack search messages` で `mcp__claude_ai_Slack__*` がヒットすれば MCP は使用可能（CLI 認証が失効していても MCP 経路は別ルートで生きている）
  - `claude mcp list` で `claude.ai Slack: ✓ Connected` を確認できれば MCP は最優先で使う
  - `slackcli` が `invalid_auth` を返しても、それは CLI の Slack トークン失効であり、MCP の認証状態とは無関係
- **GitHub**: 本日のコミット・PR・レビュー・Issue コメント/更新を `gh` で取得

この結果を Step 2・3 で再利用する（二重取得しない）。

### Step 2: github-issues（open issue 確認）

`/github-issues` スキルの `list` に従い、`cmb-sy` にアサインされた open issue を組織横断で取得して表示する（read-only）。

- ファイル連携・task.md 同期は行わない（純粋な issue 一覧）
- 当日の作業の文脈把握が目的。クローズ・作成等の操作が必要なら、ユーザーが明示的に `/github-issues` を別途実行する

### Step 3: daily-log（セッション + CloudLog）

以下と等価な処理を実行する:

```
/daily-log --session --cloudlog --exclude siori --exclude generate-video --exclude shindanshi --exclude microsoft-agent-hackathon --exclude kunstSite --exclude dotfiles [追加 --exclude ...]
```

- Step 1 で取得済みの Slack + GitHub 情報をそのまま使う（再取得しない）
- Claude Code セッションログを走査し、`## 今日の成果` セクションを生成
- 対応表に従い CloudLog エントリを生成

### Step 4: CloudLog 入力

Step 0 で「Step 4」がスキップ選択されている場合は本ステップ全体をスキップし、完了報告に「CloudLog 入力: スキップ」と記録する。

スキップしない場合は Playwright でブラウザを開き、Step 3 で生成したエントリを自動入力する。

→ 詳細は daily-log の「Step CL: CloudLog 入力実行」を参照。

### Step 5: generate-problem（振り返り）

Step 0 で「Step 5」がスキップ選択されている場合は本ステップ全体をスキップし、完了報告に「generate-problem: スキップ」と記録する。

スキップしない場合は `/generate-problem` スキルに従い、本日の作業を問題形式で振り返る。

- Step 3 の「今日の成果」と daily-log の内容を素材として使う（再収集しない）
- 結果は日報と `01_quant/過去問.md` に記録される

### Step 5.5: 北極星ロースト更新（毎日）

`$HOME/develop/obsidian/01_quant/北極星.md` 冒頭の `<!-- ROAST:START -->` 〜 `<!-- ROAST:END -->` ブロックを、当日の実測データで丸ごと再生成する。**毎日実行する**。Step 0 のスキップ対象には含めない（generate-problem がスキップされても実行する）。

**データ収集**（数字はすべて実測する。推測・前回値の流用で書かない）:

1. **経過日数**: 北極星.md の frontmatter `updated`（実質更新日）から本日までの日数
2. **読了率**: 直近30日に存在するデイリーノート（本日以前のみ。未来日付のデイリーは除外）のうち、始まりジョブに `[[01_quant/北極星|北極星]]` のチェック行を持つもの（2026-07-10 以前の旧リンク `[[01_quant/約束の銘記|約束の銘記]]` も同一視）を分母とし、`- [x]` になっている日数を分子とする
3. **週次レビュー遵守**: 北極星の更新履歴テーブルの最新行の日付が7日以内か

**生成ルール**:

- `> [!danger] まず現実を見ろ（YYYY-MM-DD 時点）` で始まる callout、4〜6行
- 1行目は固定: 「この文書は「北極星」と「約束の銘記」の統合版であり、お前の唯一のコア文書だ。」
- 実測の数字を必ず本文に入れる。数字を伴わない説教は書かない
- トーンは常に辛口・二人称（お前）。段階:
  - 経過 ≤ 7日 かつ 読了率 ≥ 80% → 辛口キープ。褒めない（「最低限やっただけだ」の温度）
  - どちらか未達 → 未達の数字を名指しで詰める
  - 経過 > 21日 または 読了率 < 50% → 最大火力。放置日数・空欄日数を突きつける
- 締めは必ず「この数字は /eod のたびに更新される」＋逃げ場を塞ぐ1行
- ROAST マーカー行自体（`<!-- ROAST:START ... -->` / `<!-- ROAST:END -->`）は残す
- **禁止**: このステップで frontmatter `updated` と更新履歴を書き換えること。ロースト再生成は「実質更新」に数えない（触ると経過日数が自己リセットし、指標が無意味になる）。`updated` と更新履歴を動かしてよいのは、金曜の週次レビューによる本文修正のみ（vault 側 `/eod` の週次レビュー手順を参照）

### Step 6: 翌日デイリー作成

翌日の日報ファイルを `03_warehouse/daily_template.md` から複製する。

**前提**:
- テンプレート: `$HOME/develop/obsidian/03_warehouse/daily_template.md`
- 出力先: `$HOME/develop/obsidian/00_daily/{YYYY}年/{M}月/{D}日({曜}).md`
- 命名規則: 月・日はゼロパディングなし（`5月/14日(木).md`）。曜日は日本語1文字（月火水木金土日）

**処理**:
1. 翌日の日付を計算する（macOS では `date -v+1d` を使う）。年跨ぎ・月跨ぎを正しく扱うこと
   - 年: `date -v+1d +%Y` → `2026`
   - 月: `date -v+1d +%-m` → `5`（先頭ゼロ抜き）
   - 日: `date -v+1d +%-d` → `14`（先頭ゼロ抜き）
   - 曜日番号: `date -v+1d +%u` → 1=月, 2=火, 3=水, 4=木, 5=金, 6=土, 7=日
2. 出力先パスを組み立てる: `00_daily/{年}年/{月}月/{日}日({曜}).md`
3. 出力先ファイルが既に存在する場合は何もせず、完了報告に「既に存在のためスキップ」と記録する（**上書き禁止**）
4. 親ディレクトリが存在しなければ `mkdir -p` で作成する
5. `cp` でテンプレートを複製する。テンプレート内容は一切編集しない
6. 完了報告に作成したファイルのフルパスを記録する

**注意**:
- 本日の日報内「終わりのジョブ → 明日のデイリーの作成」のチェックボックスは自動で `[x]` にしないこと。手動運用の余地を残す
- テンプレートの内容（`[[]]` リンク・タグ・色タグ）は複製時点では1文字も書き換えないこと（`## 今日やること` へのタスク書き込みは Step 7 が担う）

### Step 7: 翌日タスク整理（GitHub issue 紐付け）

Step 6 の翌日デイリー（既に存在していた場合も対象）の `## 今日やること` セクションにタスクを書き込む。まず本日の未チェックタスクを自動で引き継ぎ、その後ユーザーから新規タスクを受け取って GitHub issue と紐付ける。

**Step 7-0: 未チェックタスクの自動引き継ぎ（コピー・必須）:**

新規タスクを尋ねる前に、本日の日報の `## 今日やること` にある `- [ ]`（未チェック）タスクを翌日デイリーの `## 今日やること` へ**コピー**する:

- **コピー**であり移動ではない。本日の日報の該当行は**そのまま残す**（日報はその日の記録として不変）
- 対象は未チェック（`- [ ]`）行のみ。`- [x]`（完了）行は引き継がない
- **ネストした子項目・既存の issue リンクは原文のまま保持**する（例: `- [ ] ブログ対応` とその子 `\t- [ ] …`、`- [ ] [勉強会準備](URL)` のリンクを維持）
- 引き継ぎ後の翌日デイリーは、既に同じタスクが書かれていれば**重複させない**（テキスト一致でスキップ。idempotent）
- 引き継ぎ先の構造は**フラット**（`## 今日やること` 見出し直下に `- [ ]` を順に並べる。`- メイン`/`- 雑務` の入れ子にはしない — 実運用のデイリーはフラット構造）

**新規タスクの受け取り:**
1. 引き継ぎ結果を提示したうえで、ユーザーに「他に明日やる新規タスクはあるか」を尋ねる。参考として Step 2 の open issue 一覧（cmb-sy assigned。無ければここで `/github-issues` list）も併せて提示する
2. 「なし」「スキップ」の回答なら新規追加はせず（引き継ぎ分はそのまま）、完了報告に「新規タスク: なし」と記録する

**GitHub issue との照合:**
3. 各タスクを open issue 一覧とタイトル・内容で意味的に照合する
   - 一致する issue がある → タスク行に issue リンクを差し込む
   - 候補が複数ある・確信が持てない → `AskUserQuestion`（header: `issue紐付け`）で候補 issue（`#{number} {タイトル}`）を選択肢として提示して確定する。推測で紐付けを確定しない
4. 一致する issue がないタスクは、`AskUserQuestion`（header: `新規issue`、multiSelect: `true`）で「どのタスクを新規 issue として作成しますか?」と尋ねる。選択肢は該当タスク名（4 件超は複数回に分割）
5. 作成対象に選ばれた各タスクは `/github-issues` の create フローに従って issue を作成する。create フローの Step 1〜2 が「どのプロジェクト（repo）か」の確認を、Step 3〜4 が「詳細のヒアリングとドラフト擦り合わせ」を担うため、eod 側でこれらを簡略化・省略しない。作成後に返る issue URL をタスク行に差し込む
6. 作成しないと選ばれたタスクはリンクなしのタスク行として書く

**書き込み:**
- 対象セクションの見出しは色タグ付き（`## <font color="#81A1C1">今日やること</font>`）。daily-log 同様、色タグあり・なし両対応で「今日やること」を含む見出し行を探す。見出し行自体は変更しない
- **フラット構造**: 引き継ぎ分・新規分とも `## 今日やること` 見出し直下に `- [ ]` を順に並べる（`- メイン`/`- 雑務` の入れ子は使わない）。テンプレ由来の `[[01_quant/キャリア]]を確認`・`[Githubタスク](...)`・`- メイン`/`- 雑務` の空プレースホルダ行が残っていれば、フラットなタスク行に置き換える
- 並び順: 引き継ぎタスク（本日の順序を保持）→ 新規タスク（受け取り順）
- issue 紐付けありのタスク行: `- [ ] {タスク内容}（[{repo}#{number}]({issue の URL})）`。`{repo}` は org 修飾なしのリポジトリ名（org は Resily 固定）
  - 例: `- [ ] anonymize ETL の k 値見直し（[data-platform#42](https://github.com/Resily/data-platform/issues/42)）`
- リンクなしのタスク行: `- [ ] {タスク内容}`
- 引き継ぎタスクの issue リンクは原文を保持する（新規の issue 照合は新規タスクのみが対象）
- 翌日デイリーが既存でタスク行が既に書かれている場合は、既存行の文言を保持したまま重複追加を避け、issue 未紐付けの新規タスクにのみリンク差し込みを行う
- `## 今日やること` 以外のセクションは変更しない

### Step 8: Obsidian vault を commit & push

eod で生じた vault の全変更（日報・`01_quant/過去問.md`・翌日デイリー・`02_projects/` 等）を
git でコミットし、リモートへ push する。**最後に実行する**（前のステップが一部失敗しても、
ここまでに生成・更新されたファイルは確実に保存する）。

**前提:**
- vault: `$HOME/develop/obsidian`（git リポジトリ、upstream `origin/main`、
  リモートは private `cmb-sy/obsidian`）
- 全コマンドは `git -C $HOME/develop/obsidian ...` で実行し、`cd` しない

**処理:**
1. `git -C <vault> status --porcelain` で変更の有無を確認する。0件なら commit/push を
   スキップし、完了報告に「変更なし」と記録する
2. 変更がある場合:
   - `git -C <vault> add -A`
   - `git -C <vault> commit -m "eod: $(date +%F) 日次締め（日報・振り返り・翌日デイリー）"`
     - `eod:` 接頭辞で、Obsidian Git プラグインの定期 `vault backup:` コミットと区別する
     - フックをスキップしない（`--no-verify` 禁止）
   - `git -C <vault> push`
3. push が失敗した場合（non-fast-forward 等。別マシン / プラグインが先に push した可能性）:
   - **force push は禁止**。`git -C <vault> pull --rebase` を試み、競合がなければ再 push する
   - rebase が競合した場合はそこで停止し、エラー内容を完了報告に記録して手動解決を促す

**注意:**
- vault には作業メモや Slack 引用が含まれうるが、push 先は本人の **private** リポジトリで、
  Obsidian Git プラグインの定期バックアップと同一リモート。新たな公開は発生しない
- commit せず push だけ、のような中途状態を作らない。commit が成功した時のみ push する

---

## 完了報告

- 更新した日報ファイルパス
- github-issues: open issue 件数（cmb-sy assigned）
- CloudLog 入力件数・合計時間
- 走査したセッション数・除外プロジェクト
- generate-problem 結果（正解率 / スキップ時は「スキップ」）
- 北極星ロースト更新: 経過日数・読了率（分子/分母）・適用したトーン段階
- 翌日デイリー作成（作成したパス or「既に存在のためスキップ」）
- 翌日タスク整理: タスク件数の内訳（issue 紐付け n 件 / 新規 issue 作成 n 件 / リンクなし n 件。タスクなしなら「なし」）
- Obsidian vault: commit ハッシュ（短縮）+ push 結果（変更なしならその旨 / push 失敗なら理由）
