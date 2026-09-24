---
name: eod
description: >-
  1 日の作業を締めたいとき（終業時・日報作成時）に使うオーケストレータ。
  Slack+GitHub+distill-gain-latest-info+github-sync 計画の並列収集 → open issue 確認 → GitHub Issue の TaskNotes 同期 → 日報生成 → CloudLog 入力 → 翌日デイリー作成 → 翌日タスクの GitHub issue 紐付け → Obsidian vault commit/push を実行する。
  除外プロジェクト指定は本文の Options を参照。
argument-hint: "[--exclude <キーワード>...]"
user-invocable: true
---

その日の作業を1コマンドで締める。**並列収集（Slack+GitHub+distill-gain-latest-info watch+github-sync 計画）→ github-issues（open issue 確認）→ github-sync 適用 → 完了タスクの削除 → daily-log → CloudLog入力 → 翌日デイリー作成 → 翌日タスク整理（↩️ が付いたタスクの引き継ぎ＋GitHub issue 紐付け）→ Obsidian vault commit/push** を順次実行する。

## Options

| Option | 効果 |
|--------|------|
| `--exclude <キーワード>...` | 日報生成の対象から除外するプロジェクトを追加する。下記デフォルトに **合算** される（デフォルトを置き換えない） |

デフォルトで `--exclude siori --exclude generate-video --exclude shindanshi --exclude microsoft-agent-hackathon --exclude kunstSite --exclude dotfiles --exclude body-management --exclude household-accounts` を適用する。

---

## 実行フロー

### Step 0: スキップ対象の対話確認（必須・最初に実施）

**起動直後・他のステップに着手する前に必ず実施する**。`AskUserQuestion` を **1 回だけ**呼び、下記 1 問を提示してスキップ対象を選ばせる（選択肢は最大 4 件、`multiSelect: true`）。

**Q1**「スキップ対象を確認させてください。どのステップを飛ばしますか?」（header: `Skip対象`）— 順序固定:
  1. `Step 4: CloudLog 自動入力` — Playwright での CloudLog 入力をスキップ(稼働時間も尋ねない)
  2. `github-sync` — GitHub Issue → TaskNotes 同期をスキップ(Step 2.5 も併せてスキップ)

**作業記録の収集（Step 1 の Slack / GitHub / セッションログ）はスキップできない。** 選択肢に出さず、`Other` で申し出があっても受けない。日報の `## 今日の成果` はこの 3 つが揃って初めて成立し、1 つ欠けるとその日の記録が恒久的に穴になる。収集は読み取りのみで副作用が無く、失敗しても後続を止めないため、飛ばす利得が無い。取得に失敗した場合は「取得失敗」として続行する（スキップとは区別する）。

Step 3(daily-log 自体のスキップ) などその他のスキップは `Other` (自由記述) で受け付ける。ユーザーが何も選択しなかった場合は「全ステップ実行」とみなす。選択結果は実行フロー全体で参照する。

**重要**:
- `--skip-*` 系のフラグ引数は受け付けない。引数で渡されてもこの質問は省略しない
- 質問は1回だけ。Step 1 以降に進んでから「やっぱりスキップしたい」が出ても再質問せず、ユーザーが /eod を再実行する想定
- Step 3 がスキップされた場合は Step 4(CloudLog 入力) も自動的にスキップする(エントリ未生成のため)
- Step 1 の Slack/GitHub 収集が**失敗**した場合（認証切れ・レート制限等）、daily-log は取得できた情報だけで成果セクションを生成し、完了報告に「取得失敗: {ジョブ名} / {理由}」と明記する。スキップという扱いはしない

### Step 1: 情報収集（並列）

以降のステップで使い回すため、最初に一括取得する。**4 ジョブを 1 メッセージ内で同時に発射する**(Bash 呼び出しは同一メッセージ内の並列 tool call、distill-gain-latest-info のみサブエージェント)。Slack 収集・GitHub 活動収集は**常に発射する**（Step 0 でスキップ対象にできない）。github-sync 計画生成のみ、Step 0 でスキップ選択されていれば発射しない。

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
- **distill-gain-latest-info watch**: サブエージェントに `distill-gain-latest-info` スキルを `watch` で実行させる
  - サブエージェントへの指示に「確認が要る事項は `## 改善提案` 節に書いて返す。サブエージェント内で適用しない」ことを明記する
  - vault への commit は行わせない（Step 7 が一括で行う）
- **github-sync 計画生成**: `python3 $HOME/develop/obsidian/03_system/skills/github-sync/sync.py --plan-file /private/tmp/eod-github-sync-plan.md`
  - 書き込みなしの計画生成のみ。`--apply` と `--push` はここでは絶対に付けない（適用は Step 2.5、push は Step 7）
  - 一時ファイルは `/private/tmp` 配下に置く（macOS の `$TMPDIR` は `/var/folders` 配下でツール側のガードに抵触する）

Slack + GitHub の結果を Step 2・3 で再利用する（二重取得しない）。

### Step 1.5: 情報収集の改善提案

Step 1 の `distill-gain-latest-info` が書いたダイジェスト
(`$HOME/develop/distill-vault/情報収集/YYYY-MM-DD.md`) の `## 改善提案` 節を読む。
節が無い、または項目が 0 件なら本ステップをスキップし、完了報告に「改善提案: なし」と記録する。

項目があれば `AskUserQuestion`(`multiSelect: true`, header: `監視先`) で採否を問い、
**承認されたものだけ**を `$HOME/dotfiles/claude/skills/distill-gain-latest-info/sources.yaml` に反映する。

- 承認なしに `sources.yaml` を書き換えない
- 反映後、変更した行を完了報告に列挙する
- サブエージェントは提案を書くだけで適用しない。適用はここでのみ行う

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

### Step 2.6: 完了から 14 日を過ぎた TaskNotes を削除

**github-sync がスキップされていても実行する。** かんばんに完了タスクが溜まり続けるのを防ぐのが目的で、
GitHub への書き込みを伴わないため github-sync の採否とは独立している。

**Step 2.5 で `sync.py --apply` を実行した場合は、その中で削除済みなので本ステップをスキップする。**

削除対象は `sync.py` の `plan_purge()` で列挙する。保護対象には Step 2 で取得した
open issue の URL を渡す（同じ一覧を二度取らない）。

```python
import importlib.util, datetime
spec = importlib.util.spec_from_file_location("sync", "03_system/skills/github-sync/sync.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
stale, undated = m.plan_purge(datetime.date.today(), open_urls)
```

- 戻り値は `(パス, 完了日, 手書きメモの有無)` の 3 要素タプル
- 判定は `completedDate` のみ。`dateModified` や mtime は使わない
- **完了日が無いものは削除しない。** 今日 done にしたばかりのタスクを消す事故を防ぐため、
  `undated` として別枠で報告する
- GitHub 側が open かつ自分の担当のままのノートは削除しない（消すと次の同期で復活し、
  Obsidian 側で done にした事実が失われる）

**削除は破壊的操作なので、件数と内訳を提示して承認を得てから実行する。**

- **手書きメモを持つノートの件数と名前を必ず提示する。** メモごと消えるため
- 完了日の分布（いつ done になったものが対象か）を添える
- 承認が得られなければ何もしない。件数だけ完了報告に記録する
- 復元は git 履歴から可能である旨を伝える（`git show <commit>^:tasks/Tasks/{ファイル名}`）

削除したファイルは Step 7 の commit に含まれる。

### Step 2.7: 1 週間を過ぎた作業記録とダイジェストを捨てる

distill の正本（`$HOME/develop/distill-vault`）から、7 日より前の
`プロジェクト/*/記録/*.md` と `情報収集/*.md` を削除する。**承認は求めず、そのまま実行する。**

```bash
~/develop/other/distill-of-ai-process/.venv/bin/distill purge --days 7 --apply
```

- 記録とダイジェストはその日の作業を写したもので、要点は `概要.md` と学習メモへ移った後。
  原文を残し続けると一覧が埋まり、読むべきものが見えなくなる
- **`概要.md` / `用語.md` / `学習メモ/` は対象外。** purge は記録とダイジェストしか見ない
- **`[[名前]]` で参照が残っているものは自動で保護される。** リンクが宙に浮かないため、
  「消したらリンクが切れた」は起きない。保護された件数は出力に出る
- **`除外.md` に書かれたものは日付を問わず消える。** 出さないと決めたものを日付が
  来るまで置く理由がないため。参照の保護はこちらにも効く。除外したのに消えて
  ほしくないものがあれば、`除外.md` から行を外す
- **除外していないもので、ファイル名が規約外のものは消さない。** 日付を決められない
  ものは残して報告する。`除外.md` で名指ししたものは、日付を読めなくても消える
- 復元は git 履歴から可能（`git -C ~/develop/distill-vault show <commit>^:<パス>`）。
  distill の配信ジョブが 5 分ごとに自動 commit するため、削除は必ず履歴に残る
- 出力の「削除 n 件 / 保護 n 件」を完了報告にそのまま載せる。**承認を求めない代わりに、
  何が消えたかは必ず見えるようにする**

TaskNotes の削除（Step 2.6）とは対象も置き場所も別。あちらは Obsidian の
かんばん、こちらは distill の正本。

### Step 3: daily-log（セッション + CloudLog）

以下と等価な処理を実行する:

```
/daily-log --session --cloudlog --exclude siori --exclude generate-video --exclude shindanshi --exclude microsoft-agent-hackathon --exclude kunstSite --exclude dotfiles --exclude body-management --exclude household-accounts [追加 --exclude ...]
```

- Step 1 で取得済みの Slack + GitHub 情報をそのまま使う（再取得しない）
- Claude Code セッションログを走査し、`## 今日の成果` セクションを生成
- **収集した情報のうちプロジェクトの中身が変わったものは `$HOME/develop/distill-vault/プロジェクト/{PJ}/概要.md` に反映する。**
  それ以外はすべて「今日の成果」へ。振られたタスクはどちらにも書かない（かんばんの領分）。
  判定と歯止めは daily-log の Step 6 に従う
- 対応表に従い CloudLog エントリを生成

### Step 4: CloudLog 入力

Step 0 で「Step 4」がスキップ選択されている場合は本ステップ全体をスキップし、完了報告に「CloudLog 入力: スキップ」と記録する。

スキップしない場合は Playwright でブラウザを開き、Step 3 で生成したエントリを自動入力する。

→ 詳細は daily-log の「Step CL: CloudLog 入力実行」を参照。

### Step 4.5: 日次評価（daily-score）

Step 3 の daily-log より**後**に実行する。今日の成果が書かれてから集計する必要があるため。

```
/daily-score
```

daily-score が行うこと:

1. 振り返りが空なら一言促す（スキップ可）
2. Forest 時間を 1 回聞く（スキップ可）
3. distill の学習メモから 4 択 5 問を出し、正解率を出す（スキップ可）
4. `01_daily/{YYYY}年/日次評価.md` の表へ 1 行 upsert
5. その日のデイリーの `## 評価` へ AI のコメントを書く

**スキップした項目は `—` で記録される。** 入力が無くても行は積み上がる。

**Step 0 のスキップ対象には入れない。** 振り返り・Forest・クイズを個別に
飛ばせるので、ステップ全体を飛ばす必要がない。自動集計の 5 列だけでも
記録する価値がある。

### Step 5: 翌日デイリー作成

翌日の日報ファイルを `03_system/daily_template.md` から複製する。

**前提**:
- テンプレート: `$HOME/develop/obsidian/03_system/daily_template.md`
- 出力先: `$HOME/develop/obsidian/01_daily/{YYYY}年/{M}月/{D}日({曜}).md`
- 命名規則: 月・日はゼロパディングなし（`5月/14日(木).md`）。曜日は日本語1文字（月火水木金土日）

**処理**:
1. 翌日の日付を計算する（macOS では `date -v+1d` を使う）。年跨ぎ・月跨ぎを正しく扱うこと
   - 年: `date -v+1d +%Y` → `2026`
   - 月: `date -v+1d +%-m` → `5`（先頭ゼロ抜き）
   - 日: `date -v+1d +%-d` → `14`（先頭ゼロ抜き）
   - 曜日番号: `date -v+1d +%u` → 1=月, 2=火, 3=水, 4=木, 5=金, 6=土, 7=日
2. 出力先パスを組み立てる: `01_daily/{年}年/{月}月/{日}日({曜}).md`
3. 出力先ファイルが既に存在する場合は何もせず、完了報告に「既に存在のためスキップ」と記録する（**上書き禁止**）
4. 親ディレクトリが存在しなければ `mkdir -p` で作成する
5. `cp` でテンプレートを複製する。テンプレート内容は一切編集しない
6. 完了報告に作成したファイルのフルパスを記録する

**注意**:
- 本日の日報内「終わりのジョブ → 明日のデイリーの作成」のチェックボックスは自動で `[x]` にしないこと。手動運用の余地を残す
- テンプレートの内容（`[[]]` リンク・タグ・色タグ）は複製時点では1文字も書き換えないこと（`## 今日やること` へのタスク書き込みは Step 6 が担う）

### Step 6: 翌日タスク整理（GitHub issue 紐付け）

Step 5 の翌日デイリー（既に存在していた場合も対象）の `## 今日やること` セクションにタスクを書き込む。本日の `↩️`（次の日に持ち越し）が付いたタスクを引き継ぎ、リンクの無いタスク行を GitHub issue と紐付ける。

**明日やることを問いかけない。** 何を明日へ回すかは `↩️` で本人が表明済みであり、そのうえでさらに尋ねると同じ判断を 2 回させることになる。新規に思いついたものは本人が Obsidian へ直接書く。

**Step 6-0: ↩️ が付いたタスクの引き継ぎ（コピー・必須）:**

本日の日報の `## 今日やること` にある **`↩️` が付いた未チェックタスク**を翌日デイリーの `## 今日やること` へ**コピー**する:

- **引き継ぐのは `↩️`（次の日に持ち越し）が付いた行だけ。** 未チェックというだけでは引き継がない。
  何を明日へ回すかは本人が ⌥⌘M で印を付けて決めるものであり、残っている全部を自動で送ると
  翌日のリストが捌けない量に膨らむ
- **コピー**であり移動ではない。本日の日報の該当行は**そのまま残す**（日報はその日の記録として不変）
- 未チェック（`- [ ]`）行のみ。`- [x]`（完了）行は `↩️` が付いていても引き継がない
- **コピー先では `↩️` を外す。** 印は「その日に下した判断」であって、付けたまま送ると翌日以降も
  自動で乗り続け、毎日の仕分けにならない。翌日また回すなら、その日にもう一度印を付ける
- `↩️` が 1 件も無ければ引き継ぎ 0 件として報告し、次へ進む。
  **「印の付け忘れではないか」と確認したり、代わりに未チェック行を引き継いだりしない**
- **ネストした子項目・既存の issue リンクは原文のまま保持**する（例: `- [ ] ブログ対応` とその子 `\t- [ ] …`、`- [ ] [勉強会準備](URL)` のリンクを維持）
- 引き継ぎ後の翌日デイリーは、既に同じタスクが書かれていれば**重複させない**（テキスト一致でスキップ。idempotent）
- **引き継ぎ先はテンプレートの達成段階（`##### ミニマムサクセス` / `##### フルサクセス` / `##### エクストラサクセス`）を維持し、本日の同じ段階へコピーする。** この見出し構造には `slack-daily-post`（投稿の組み立て）と `link-inprogress-tasks`（タスクリンク）が依存しており、フラット化すると両方が壊れる

**GitHub issue との照合:**

対象は**翌日デイリーにある issue リンクを持たないタスク行**（引き継いだもの・本人が手で書いたもののどちらも）。リンクが既にある行は触らない。0 件ならこの節をまるごと飛ばす。

1. 対象を Step 2 の open issue 一覧（cmb-sy assigned。無ければここで `/github-issues` list）とタイトル・内容で意味的に照合する
   - 一致する issue がある → タスク行に issue リンクを差し込む
   - 候補が複数ある・確信が持てない → `AskUserQuestion`（header: `issue紐付け`）で候補 issue（`#{number} {タイトル}`）を選択肢として提示して確定する。推測で紐付けを確定しない
2. 一致する issue がないタスクは、`AskUserQuestion`（header: `新規issue`、multiSelect: `true`）で「どのタスクを新規 issue として作成しますか?」と尋ねる。選択肢は該当タスク名（4 件超は複数回に分割）
3. 作成対象に選ばれた各タスクは `/github-issues` の create フローに従って issue を作成する。create フローの Step 1〜2 が「どのプロジェクト（repo）か」の確認を、Step 3〜4 が「詳細のヒアリングとドラフト擦り合わせ」を担うため、eod 側でこれらを簡略化・省略しない。作成後に返る issue URL をタスク行に差し込む
4. 作成しないと選ばれたタスクはリンクなしのタスク行のまま残す

**書き込み:**
- 対象セクションの見出しは色タグ付き（`## <font color="#81A1C1">今日やること</font>`）。daily-log 同様、色タグあり・なし両対応で「今日やること」を含む見出し行を探す。見出し行自体は変更しない
- **達成段階の見出しは維持する**: タスク行は各 `#####` 見出しの配下に置く。空の `- [ ]` プレースホルダ行があれば先に埋める
- 並び順: 本日の順序を保持する
- issue 紐付けありのタスク行: `- [ ] {タスク内容}（[{repo}#{number}]({issue の URL})）`。`{repo}` は org 修飾なしのリポジトリ名（org は Resily 固定）
  - 例: `- [ ] anonymize ETL の k 値見直し（[data-platform#42](https://github.com/Resily/data-platform/issues/42)）`
- リンクなしのタスク行: `- [ ] {タスク内容}`
- 既にある issue リンクは原文を保持する。照合はリンクを持たない行だけが対象
- 翌日デイリーにタスク行が既に書かれている場合は、文言を保持したまま重複追加を避ける
- `## 今日やること` 以外のセクションは変更しない

### Step 7: Obsidian vault を commit & push

eod で生じた vault の全変更（日報・翌日デイリー等）を
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
- 更新したプロジェクト概要（ファイル・節・根拠。無ければ「変更なし」）
- github-issues: open issue 件数（cmb-sy assigned）
- distill-gain-latest-info watch: 観測したスコープとダイジェストの保存先（スキップ時は「スキップ」）
- github-sync: 新規作成 / 更新 / done へ変更 の件数（スキップ時は「スキップ」）
- TaskNotes の削除: 件数（うち手書きメモあり n 件 / 完了日なしで見送り n 件。承認されなければ「見送り」）
- distill purge: 削除 n 件（記録 n / 情報収集 n）、参照ありで保護 n 件
- CloudLog 入力件数・合計時間
- 走査したセッション数・除外プロジェクト
- 翌日デイリー作成（作成したパス or「既に存在のためスキップ」）
- 翌日タスク整理: ↩️ で引き継いだ n 件、その内訳（issue 紐付け n 件 / 新規 issue 作成 n 件 / リンクなし n 件。引き継ぎ 0 件なら「なし」）
- Obsidian vault: commit ハッシュ（短縮）+ push 結果（変更なしならその旨 / push 失敗なら理由）
