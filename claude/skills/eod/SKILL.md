---
name: eod
description: >-
  1 日の作業を締めたいとき（終業時・日報作成時）に使うオーケストレータ。
  Slack+GitHub+distill-gain-latest-info+github-sync 計画の並列収集 → open issue 確認 → GitHub Issue の TaskNotes 同期 → 日報生成 → CloudLog 入力 → 翌日デイリー作成 → 翌日タスクの GitHub issue 紐付け → Obsidian vault commit/push を実行する。
  除外プロジェクト指定は本文の Options を参照。
argument-hint: "[--exclude <キーワード>...]"
user-invocable: true
---

その日の作業を1コマンドで締める。**並列収集（Slack+GitHub+distill-gain-latest-info watch+github-sync 計画）→ github-issues（open issue 確認）→ github-sync 適用 → daily-log → CloudLog入力 → 翌日デイリー作成 → 翌日タスク整理（未チェックの自動引き継ぎ＋新規の GitHub issue 紐付け）→ Obsidian vault commit/push** を順次実行する。

## Options

| Option | 効果 |
|--------|------|
| `--exclude <キーワード>...` | 日報生成の対象から除外するプロジェクトを追加する。下記デフォルトに **合算** される（デフォルトを置き換えない） |

デフォルトで `--exclude siori --exclude generate-video --exclude shindanshi --exclude microsoft-agent-hackathon --exclude kunstSite --exclude dotfiles --exclude body-management --exclude household-accounts` を適用する。

---

## 実行フロー

### Step 0: スキップ対象の対話確認（必須・最初に実施）

**起動直後・他のステップに着手する前に必ず実施する**。`AskUserQuestion` を **1 回だけ**呼び、下記 2 問を同時に提示してスキップ対象を選ばせる（1 問あたり選択肢は最大 4 件、どちらも `multiSelect: true`）。

**Q1**「スキップ対象を確認させてください。どのステップを飛ばしますか?」（header: `Skip対象`）— 順序固定:
  1. `Step 4: CloudLog 自動入力` — Playwright での CloudLog 入力をスキップ(稼働時間も尋ねない)
  2. `Step 1: Slack 収集` — 本日の Slack 発言・関与スレッド取得をスキップ
  3. `Step 1: GitHub 収集` — 本日のコミット・PR・Issue 活動取得をスキップ

**Q2**「Step 1 の追加ジョブで飛ばすものはありますか?」（header: `追加Skip`）— 順序固定:
  1. `distill-gain-latest-info watch` — 技術情報の横断観測をスキップ(Web 検索を多用し所要時間が伸びるため、急ぐ日はここで外す)
  2. `github-sync` — GitHub Issue → TaskNotes 同期をスキップ(Step 2.5 も併せてスキップ)

Step 3(daily-log 自体のスキップ) などその他のスキップは `Other` (自由記述) で受け付ける。ユーザーが何も選択しなかった場合は「全ステップ実行」とみなす。選択結果は実行フロー全体で参照する。

**重要**:
- `--skip-*` 系のフラグ引数は受け付けない。引数で渡されてもこの質問は省略しない
- 質問は1回だけ。Step 1 以降に進んでから「やっぱりスキップしたい」が出ても再質問せず、ユーザーが /eod を再実行する想定
- Step 3 がスキップされた場合は Step 4(CloudLog 入力) も自動的にスキップする(エントリ未生成のため)
- Step 1 Slack/GitHub 片方または両方がスキップされた場合、daily-log は走査したセッション情報のみで成果セクションを生成する(取得失敗とは区別し「スキップにより未取得」と完了報告に明記)

### Step 1: 情報収集（並列）

以降のステップで使い回すため、最初に一括取得する。**4 ジョブを 1 メッセージ内で同時に発射する**(Bash 呼び出しは同一メッセージ内の並列 tool call、distill-gain-latest-info のみサブエージェント)。Step 0 でスキップ選択されたジョブは発射しない(全ジョブがスキップなら Step 1 全体をスキップ)。

| ジョブ | 実行方法 | 結果の使い先 |
|--------|----------|--------------|
| Slack 収集 | MCP / CLI（下記） | Step 3 の成果セクション |
| GitHub 活動収集 | `gh` | Step 3 の成果セクション |
| distill-gain-latest-info watch | サブエージェント（下記） | Obsidian のダイジェスト（Step 7 で commit） |
| github-sync 計画生成 | Bash（下記・書き込みなし） | Step 2.5 の承認材料 |

- **Slack**: 本日の自分の発言・関与したスレッドを取得する。**取得経路は以下の優先順で必ずチェックする**:
  1. **`claude.ai Slack` MCP（最優先）** — `mcp__claude_ai_Slack__slack_search_public_and_private` を使う。`query="from:<@U07KEPWQAQN> after:{YYYY-MM-DD前日} before:{YYYY-MM-DD翌日}"`（user_id は固定）。スレッド文脈が必要な場合は `slack_read_thread`、チャンネル履歴は `slack_read_channel`
  2. **`slackcli` CLI（フォールバック）** — MCP が ToolSearch にも `claude mcp list` にも出ない場合のみ
  - **重要**: MCP ツールはセッション開始時の ToolSearch で必ず存在確認する。ToolSearch クエリ `slack search messages` で `mcp__claude_ai_Slack__*` がヒットすれば MCP は使用可能（CLI 認証が失効していても MCP 経路は別ルートで生きている）
  - `claude mcp list` で `claude.ai Slack: ✓ Connected` を確認できれば MCP は最優先で使う
  - `slackcli` が `invalid_auth` を返しても、それは CLI の Slack トークン失効であり、MCP の認証状態とは無関係
- **GitHub**: 本日のコミット・PR・レビュー・Issue コメント/更新を `gh` で取得
- **distill-gain-latest-info watch**: サブエージェントに `distill-gain-latest-info` スキルを `watch --dry-run` で実行させる
  - `--dry-run` は peers スコープの採用対話・保存だけを抑止する。サブエージェントはユーザーに質問できないため必須
  - サブエージェントへの指示に「ユーザーへの確認が必要になったら実行せず、その旨を報告して返す」ことを明記する
  - vault への commit は行わせない（Step 7 が一括で行う）
- **github-sync 計画生成**: `python3 $HOME/develop/obsidian/.claude/skills/github-sync/sync.py --plan-file /private/tmp/eod-github-sync-plan.md`
  - 書き込みなしの計画生成のみ。`--apply` と `--push` はここでは絶対に付けない（適用は Step 2.5、push は Step 7）
  - 一時ファイルは `/private/tmp` 配下に置く（macOS の `$TMPDIR` は `/var/folders` 配下でツール側のガードに抵触する）

Slack + GitHub の結果を Step 2・3 で再利用する（二重取得しない）。

### Step 2: github-issues（open issue 確認）

`/github-issues` スキルの `list` に従い、`cmb-sy` にアサインされた open issue を組織横断で取得して表示する（read-only）。

- ファイル連携・task.md 同期は行わない（純粋な issue 一覧）
- 当日の作業の文脈把握が目的。クローズ・作成等の操作が必要なら、ユーザーが明示的に `/github-issues` を別途実行する

### Step 2.5: github-sync 適用（GitHub Issue → TaskNotes）

Step 0 で「github-sync」がスキップ選択されている場合は本ステップ全体をスキップし、完了報告に「github-sync: スキップ」と記録する。

Step 1 で生成した計画ファイル（`/private/tmp/eod-github-sync-plan.md`）を使い、vault の `/github-sync` スキルの手順に従って適用する。

- 件数と削除対象を提示してユーザーの承認を得てから `sync.py --apply` を実行する。**承認なしで適用しない**（14 日より前に done になったノートの削除を含むため）
- Issue のタイトルは会話に出さない（社内プロジェクト名を含む）。詳細は計画ファイルを開いてもらう
- `--push` は付けない。commit/push は Step 7 が一括で行う
- 適用後に「本文が薄い」と列挙されたノートへの補足追記まで行う（github-sync スキルの該当手順に従う）

ここで生成された TaskNotes は Step 6（翌日タスク整理）の材料になる。

### Step 3: daily-log（セッション + CloudLog）

以下と等価な処理を実行する:

```
/daily-log --session --cloudlog --exclude siori --exclude generate-video --exclude shindanshi --exclude microsoft-agent-hackathon --exclude kunstSite --exclude dotfiles --exclude body-management --exclude household-accounts [追加 --exclude ...]
```

- Step 1 で取得済みの Slack + GitHub 情報をそのまま使う（再取得しない）
- Claude Code セッションログを走査し、`## 今日の成果` セクションを生成
- 対応表に従い CloudLog エントリを生成

### Step 4: CloudLog 入力

Step 0 で「Step 4」がスキップ選択されている場合は本ステップ全体をスキップし、完了報告に「CloudLog 入力: スキップ」と記録する。

スキップしない場合は Playwright でブラウザを開き、Step 3 で生成したエントリを自動入力する。

→ 詳細は daily-log の「Step CL: CloudLog 入力実行」を参照。

### Step 5: 翌日デイリー作成

翌日の日報ファイルを `02_warehouse/daily_template.md` から複製する。

**前提**:
- テンプレート: `$HOME/develop/obsidian/02_warehouse/daily_template.md`
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
- テンプレートの内容（`[[]]` リンク・タグ・色タグ）は複製時点では1文字も書き換えないこと（`## 今日やること` へのタスク書き込みは Step 6 が担う）

### Step 6: 翌日タスク整理（GitHub issue 紐付け）

Step 5 の翌日デイリー（既に存在していた場合も対象）の `## 今日やること` セクションにタスクを書き込む。まず本日の未チェックタスクを自動で引き継ぎ、その後ユーザーから新規タスクを受け取って GitHub issue と紐付ける。

**Step 6-0: 未チェックタスクの自動引き継ぎ（コピー・必須）:**

新規タスクを尋ねる前に、本日の日報の `## 今日やること` にある `- [ ]`（未チェック）タスクを翌日デイリーの `## 今日やること` へ**コピー**する:

- **コピー**であり移動ではない。本日の日報の該当行は**そのまま残す**（日報はその日の記録として不変）
- 対象は未チェック（`- [ ]`）行のみ。`- [x]`（完了）行は引き継がない
- **ネストした子項目・既存の issue リンクは原文のまま保持**する（例: `- [ ] ブログ対応` とその子 `\t- [ ] …`、`- [ ] [勉強会準備](URL)` のリンクを維持）
- 引き継ぎ後の翌日デイリーは、既に同じタスクが書かれていれば**重複させない**（テキスト一致でスキップ。idempotent）
- **引き継ぎ先はテンプレートの達成段階（`##### ミニマムサクセス` / `##### フルサクセス` / `##### エクストラサクセス`）を維持し、本日の同じ段階へコピーする。** この見出し構造には `slack-daily-post`（投稿の組み立て）と `link-inprogress-tasks`（タスクリンク）が依存しており、フラット化すると両方が壊れる

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
- **達成段階の見出しは維持する**: タスク行は各 `#####` 見出しの配下に置く。段階が不明な新規タスクはミニマムサクセスに入れ、ユーザーの指定があればそれに従う。空の `- [ ]` プレースホルダ行があれば先に埋める
- 並び順: 引き継ぎタスク（本日の順序を保持）→ 新規タスク（受け取り順）
- issue 紐付けありのタスク行: `- [ ] {タスク内容}（[{repo}#{number}]({issue の URL})）`。`{repo}` は org 修飾なしのリポジトリ名（org は Resily 固定）
  - 例: `- [ ] anonymize ETL の k 値見直し（[data-platform#42](https://github.com/Resily/data-platform/issues/42)）`
- リンクなしのタスク行: `- [ ] {タスク内容}`
- 引き継ぎタスクの issue リンクは原文を保持する（新規の issue 照合は新規タスクのみが対象）
- 翌日デイリーが既存でタスク行が既に書かれている場合は、既存行の文言を保持したまま重複追加を避け、issue 未紐付けの新規タスクにのみリンク差し込みを行う
- `## 今日やること` 以外のセクションは変更しない

### Step 7: Obsidian vault を commit & push

eod で生じた vault の全変更（日報・翌日デイリー・`99_distill/` 等）を
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
- distill-gain-latest-info watch: 観測したスコープとダイジェストの保存先（スキップ時は「スキップ」）
- github-sync: 新規作成 / 更新 / done へ変更 の件数（スキップ時は「スキップ」）
- CloudLog 入力件数・合計時間
- 走査したセッション数・除外プロジェクト
- 翌日デイリー作成（作成したパス or「既に存在のためスキップ」）
- 翌日タスク整理: タスク件数の内訳（issue 紐付け n 件 / 新規 issue 作成 n 件 / リンクなし n 件。タスクなしなら「なし」）
- Obsidian vault: commit ハッシュ（短縮）+ push 結果（変更なしならその旨 / push 失敗なら理由）
