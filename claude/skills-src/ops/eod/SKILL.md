---
name: eod
description: >-
  その日の作業を1コマンドで締める。Slack+GitHub 収集 → github-issues（open issue 確認）
  → daily-log → CloudLog 入力 → generate-problem → 翌日デイリー作成 → vault commit/push を順次実行する。
argument-hint: "[--exclude <キーワード>...]"
user-invocable: true
---

その日の作業を1コマンドで締める。**Slack+GitHub収集 → github-issues（open issue 確認）→ daily-log → CloudLog入力 → generate-problem → 翌日デイリー作成 → Obsidian vault commit/push** を順次実行する。

デフォルトで `--exclude siori --exclude generate-video --exclude shindanshi --exclude microsoft-agent-hackathon --exclude kunstSite --exclude dotfiles` を適用する。`--exclude` 追加指定があれば合算する。

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

### Step 6: 翌日デイリー作成

翌日の日報ファイルを `04_warehouse/daily_template.md` から複製する。

**前提**:
- テンプレート: `/Users/snakashima/Documents/obsidian/04_warehouse/daily_template.md`
- 出力先: `/Users/snakashima/Documents/obsidian/00_daily/{YYYY}年/{M}月/{D}日({曜}).md`
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
- テンプレートの内容（`[[]]` リンク・タグ・色タグ）は1文字も書き換えないこと

### Step 7: Obsidian vault を commit & push

eod で生じた vault の全変更（日報・`01_quant/過去問.md`・翌日デイリー・`02_projects/` 等）を
git でコミットし、リモートへ push する。**最後に実行する**（前のステップが一部失敗しても、
ここまでに生成・更新されたファイルは確実に保存する）。

**前提:**
- vault: `/Users/snakashima/Documents/obsidian`（git リポジトリ、upstream `origin/main`、
  リモートは private `cmb-sy/obsidian`）
- 全コマンドは `git -C /Users/snakashima/Documents/obsidian ...` で実行し、`cd` しない

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
- 翌日デイリー作成（作成したパス or「既に存在のためスキップ」）
- Obsidian vault: commit ハッシュ（短縮）+ push 結果（変更なしならその旨 / push 失敗なら理由）
