---
name: linear-refresh
description: >-
  Linearチームのチケット棚卸し・構造整理・新規検出を一気通貫で実行するスキル。
  チケットに紐付いた外部リンクの探索に加え、キーワード検索とチケット逆引きで
  未紐付きの外部ソースも発見する。--add/--done/--list/--update で軽量 CRUD 操作も可能。
argument-hint: "[--force] [--skip-discovery] [--cleanup-only] [--add-only] [--project-update] [--daily-log] [--add [title]] [--done ID] [--list] [--update ID]"
---

# Linear Refresh

Linearチームのチケット棚卸し・構造整理・新規検出を一気通貫で実行する。

## Options

| Option | 効果 |
|--------|------|
| `--force` | Step 4 (Approve) をスキップ — Plan は表示するが即座に実行 |
| `--skip-discovery` | Step 2 (Discover) をスキップ — リンク済みソースのみ対象 |
| `--cleanup-only` | Step 3 の add 分析をスキップ |
| `--add-only` | Step 3 の cleanup 分析をスキップ |
| `--project-update` | Step 5 実行後に **`/project-update`** を連続実行し、Step 1-2 で収集した Slack/GitHub コンテキストを再利用して関連 PJ ファイルを最新化する（Step 6a） |
| `--daily-log` | 最後に **`/daily-log --session --exclude siori --exclude generate-video`** を実行して日報に集約する（Step 6b）。`--project-update` と併用可 |
| `--add [title]` | CRUD: 新規チケットを作成（title 省略時はインタラクティブ） |
| `--done ID` | CRUD: 指定チケットを Done に変更 |
| `--list` | CRUD: アクティブチケット一覧を表示 |
| `--update ID` | CRUD: 指定チケットをインタラクティブに更新 |

## Mode Detection

CRUD フラグ（`--add` / `--done` / `--list` / `--update`）が検出された場合、
**6-step ワークフローをスキップ**し、CRUD モードで直接操作を実行する。

- CRUD フラグと 6-step フラグ（`--force` 等）は**排他**。同時指定はエラー終了。
- 複数 CRUD フラグ同時指定時の処理順: `--list` → `--done` → `--add` → `--update`
- CRUD モードでは外部走査（Slack / GitHub / Obsidian）を**一切行わない**。
  Linear 内のチケットと現セッション文脈のみを対象とする。

CRUD フラグなし → 既存の 6-step ワークフロー（変更なし）。

## Prerequisites

- `linear` CLI が利用可能であること: `which linear && linear --version`
- `gh` CLI が利用可能であること: `which gh && gh auth status`
- `/slackcli` スキルが利用可能であること（Slack 探索用）
- チーム選択: `linear team list` → 1チーム: 自動選択 / 複数: ユーザーに選択を求める / 0: エラー終了

## CRUD Mode

CRUD フラグ検出時に実行される軽量操作モード。6-step ワークフローはスキップする。
外部走査（Slack / GitHub / Obsidian）は一切行わず、Linear 内チケットと現セッション文脈のみを対象とする。

### CRUD Prerequisites

- `linear` CLI: `which linear && linear --version`
- チーム解決: 既存の Prerequisites と同じ（`linear team list` → 自動選択）
- `gh` / `/slackcli` は**不要**

### Session Context Detection

CRUD オペレーション開始前に、セッションコンテキストの有無を確認する（任意、エラーにしない）:

1. `git rev-parse --show-toplevel` でリポジトリルートを取得
2. `{root}/.agents/handover/{branch}/` 配下で最新の `project-state.json` を探索
3. 見つかった場合: `active_tasks[]` から `in_progress` / `blocked` タスクを抽出して保持
4. `--add` 時の description 候補生成や `--done` 時のコメント提案に使用する
5. 見つからない場合は空コンテキストで続行

### --list: チケット一覧

アナウンス: 「CRUD: チケット一覧を取得します」

1. チケット取得:
   ```bash
   linear issue list --team {team_key} --sort priority --no-pager --limit 0
   ```
2. State でグループ化して表示:
   ```
   ## {team_key} Active Tickets (N 件)

   ### In Progress
   - {ID}: {title} [P{priority}] ({assignee})

   ### Todo
   - {ID}: {title} [P{priority}] ({assignee})

   ### Backlog
   - {ID}: {title} [P{priority}] ({assignee})
   ```
   空グループは省略。Done / Canceled は表示しない。
3. Session Context がある場合: `active_tasks` との関連を照合して末尾に表示:
   ```
   ---
   📎 Session Context: N 件の in_progress タスクあり
   - T1: {description} → 関連候補: {ID}
   ```

### --add: チケット作成

アナウンス: 「CRUD: チケットを作成します」

1. **タイトル確定:**
   - 引数あり (`--add "タスク名"`) → そのまま使用
   - 引数なし (`--add`) → AskUserQuestion: 「チケットのタイトルを入力してください」

2. **Session Context 提案:**
   - `project-state.json` が存在し `in_progress` タスクがある場合:
     AskUserQuestion: 「現在のセッションタスクと関連付けますか？」
     - 選択肢: 各 in_progress タスクの description（最大3件）+ 「関連なし」
     - 選択された場合: タスクの description / file_paths を description 候補に反映

3. **フィールド収集（AskUserQuestion で順次）:**

   a. **Priority:**
      - 選択肢: `Medium (3)` (推奨) / `High (2)` / `Low (4)` / `No priority (0)`
      - Urgent は選択肢に含めない（誤操作防止）

   b. **State:**
      - 選択肢: `Backlog` (推奨) / `Todo` / `In Progress`

   c. **Description:**
      - Session Context 候補あり → 候補を選択肢として提示 + 「空のまま」
      - Session Context なし → 「空のまま」 + Other で自由入力

4. **実行:**
   ```bash
   linear issue create --team {team_key} --title "{title}" --priority {N} --state "{state}" --description "{description}"
   ```

5. **結果表示:**
   ```
   チケットを作成しました:
   - ID: {ID}
   - Title: {title}
   - State: {state}
   - Priority: {priority_name}
   - URL: {url}
   ```

6. **Artifact 更新（ベストエフォート）:**
   `.linear-refresh/collected-context.json` が存在する場合のみ、`tickets[]` に追記。
   存在しない場合はスキップ。

### --done: チケット完了

アナウンス: 「CRUD: {ID} を Done に変更します」

1. **チケット検証:**
   ```bash
   linear issue view {ID}
   ```
   - 存在しない → エラー: 「{ID} が見つかりません」で終了
   - 既に Done → 警告: 「{ID} は既に Done です」— AskUserQuestion で続行/中止を確認
   - 既に Canceled → 警告 + 確認

2. **現在の状態を表示:**
   ```
   {ID}: {title}
   State: {current_state} → Done
   Priority: {priority}
   ```

3. **Closing comment（任意）:**
   AskUserQuestion: 「完了コメントを追加しますか？」
   - 選択肢: 「コメントなし」(推奨)
   - Session Context がある場合: 関連 in_progress タスクの summary を候補に追加
   - Other で自由入力可

4. **実行:**
   ```bash
   linear issue update {ID} --state "Done"
   ```
   コメントがある場合:
   ```bash
   linear issue comment {ID} --body "{comment}"
   ```

5. **結果表示:**
   ```
   {ID} を Done に変更しました。
   - Title: {title}
   - 変更: {old_state} → Done
   ```

6. **Artifact 更新（ベストエフォート）:**
   `collected-context.json` が存在する場合、該当チケットの `state` を更新。

### --update: チケット更新

アナウンス: 「CRUD: {ID} を更新します」

1. **チケット取得と表示:**
   ```bash
   linear issue view {ID}
   ```
   存在しない → エラー終了。

   ```
   {ID}: {title}
   State: {state} | Priority: {priority} | Assignee: {assignee}
   Labels: {labels}
   Description: {description_preview}
   ```

2. **更新フィールド選択（AskUserQuestion, multiSelect: true）:**
   - 選択肢: `State` / `Priority` / `Title` / `Description`
   - 必要に応じて Other で追加フィールド（Labels, Assignee, Due date）を指定

3. **選択されたフィールドごとに AskUserQuestion:**
   - **State:** `Backlog` / `Todo` / `In Progress` / `Done` / `Canceled`
   - **Priority:** `Urgent (1)` / `High (2)` / `Medium (3)` / `Low (4)` / `No priority (0)`
   - **Title:** Other で自由入力（現在のタイトルを表示）
   - **Description:** Session Context 候補あり → 選択肢提示。なし → Other で自由入力

4. **変更プレビュー:**
   ```
   変更内容:
   - State: {old} → {new}
   - Priority: {old} → {new}
   ```
   AskUserQuestion: 「適用しますか？」— OK / 修正 / キャンセル

5. **実行:**
   ```bash
   linear issue update {ID} --state "{state}" --priority {N} --title "{title}" ...
   ```
   変更されたフィールドのみフラグとして渡す。

6. **結果表示と Artifact 更新:** `--done` と同様のパターン。

### CRUD Error Handling

| 操作 | エラー | 対応 |
|------|--------|------|
| 共通 | `linear` CLI 未インストール/認証切れ | 案内して終了 |
| `--add` | create 失敗 | エラー表示。ステート名不正ならフォールバック（Backlog）で再試行 |
| `--done` | ID 不存在 | エラー終了 |
| `--done` | 既に Done/Canceled | 警告 + AskUserQuestion で確認 |
| `--list` | 0 件 | 「アクティブなチケットはありません」 |
| `--update` | update 失敗 | 個別フィールド失敗はスキップして残りを続行 |
| 共通 | レート制限 | 5秒待機リトライ（最大3回） |

### CRUD と Artifacts の関係

- `.linear-refresh/` artifacts に**依存しない**（artifacts なしで完全に動作する）
- `collected-context.json` が存在する場合のみベストエフォートで更新
- `plan.json` / `result.json` は CRUD からは**一切変更しない**（6-step ワークフロー専用）

---

## Workflow

```
Step 1: Collect    — チケット取得 + リンク済みURLの探索
Step 2: Discover   — キーワード検索 + チケット逆引き（--skip-discovery で省略）
Step 3: Analyze    — Cleanup + Add 分析を一括実行
Step 4: Approve    — 統合Planをユーザーに提示して承認を得る（--force で省略）
Step 5: Execute    — Linear API で変更を適用
Step 6: Chain      — 後段コマンドの連続実行（--project-update / --daily-log 指定時のみ）
```

**開始時アナウンス:** 「Linear Refresh を開始します。Step 1: Collect」

## Step 1: Collect

チケットを全件取得し、description/attachments からリンクされた外部ソースを探索する。

1. `/linear-cli` と `/slackcli` スキルを invoke する。
2. チケット一覧を取得: `linear issue list --team {id} --sort priority --all-states --all-assignees --limit 0 --no-pager`
3. アクティブチケットの詳細取得を**並列サブエージェント**でディスパッチ（10件バッチ）。
   → サブエージェント指示: [collect-agent.md](references/collect-agent.md) 「詳細取得エージェント」
4. 結果からURLを抽出。[external-source-exploration.md](references/external-source-exploration.md) に従って分類する。
5. 1ホップURL探索を**並列サブエージェント**でディスパッチ（チケットクラスタ単位）。
   → サブエージェント指示: [collect-agent.md](references/collect-agent.md) 「1ホップ探索エージェント」
6. 2ホップ条件を評価: In Progress + Urgent/High + 72時間以内のアクティビティ。
7. 該当URLがあれば、2ホップ探索を**並列サブエージェント**でディスパッチ。
   → サブエージェント指示: [collect-agent.md](references/collect-agent.md) 「2ホップ探索エージェント」
8. 全結果を [collected-context-schema.md](references/collected-context-schema.md) に従って `.linear-refresh/collected-context.json` にマージ。

## Step 2: Discover

チケットからリンクされていない外部ソースを、キーワード検索とチケット逆引きで発見する。

**`--skip-discovery` 指定時はスキップ。** 空の `discovery_sources: []` を書き込んで次へ進む。

1. collected-context.json から [discovery-strategy.md](references/discovery-strategy.md) に従ってクエリシードを生成する。
2. 以下を**並列**で実行:
   a. **Slack検索**: キーワード検索 + チケット逆引き。
      → サブエージェント指示: [discover-agent.md](references/discover-agent.md)
   b. **GitHub assigned issues 探索**: 2段階で網羅的に取得する。
      **Stage 1 — Search API（ページネーション付き）:**
      ```bash
      gh api search/issues --method GET -f q="assignee:@me is:open" -f per_page=100 --paginate --jq '.items[] | {repo: (.repository_url | split("/") | .[-2:] | join("/")), number: .number, title: .title, url: .html_url, labels: [.labels[].name], updated_at: .updated_at}'
      ```
      **Stage 2 — 所属 org のリポジトリ別補完:**
      Search API はページネーション上限（1000件）や一時的な漏れがあるため、
      所属 org の主要リポジトリを個別に走査して補完する。
      ```bash
      # org のリポジトリ一覧から対象を特定
      gh repo list <org> --json name --jq '.[].name' --limit 200
      # 各リポジトリの assigned issues を取得
      gh issue list --repo <org>/<repo> --assignee @me --state open --json number,title,url --limit 100
      ```
      対象 org は `gh api user/orgs --jq '.[].login'` で自動検出する。
      - Stage 1 + Stage 2 の結果をマージ（URL ベースで重複排除）。
      - collected-context.json の `external_sources[].url` と照合し、既に Linear にリンク済みのものを除外する。
      - 残りを `discovery_sources[]` に `tag: "[discovered:github]"` で追加する。
   c. **Obsidian プロジェクトノート探索**: 全 vault のプロジェクトフォルダを走査し、未完了タスクを抽出する。
      **Vault 検出:**
      ```bash
      find ~/Documents -maxdepth 3 -name ".obsidian" -type d 2>/dev/null
      ```
      各 vault 内でプロジェクトフォルダ（`*project*` / `*プロジェクト*`）を探索する。
      **タスク抽出ルール:**
      - 各プロジェクトの `index.md` または直接の `.md` ファイルを読み込む。
      - frontmatter の `status` が「進行中」「計画中」のものを対象とする（「完了」「アーカイブ」はスキップ）。frontmatter がないファイルも対象とする。
      - `- [ ]` 記法の未完了タスクを抽出する。テンプレート行（バッククォート内の `- [ ]`）は除外する。
      - 議事録フォルダ（`議事録/`）内の最新ファイルからもタスク（`- [ ]`）を抽出する。
      - 抽出したタスクを既存の Linear チケットタイトル・description と照合し、既に登録済みのものを除外する。
      - 残りを `discovery_sources[]` に `tag: "[discovered:obsidian]"` で追加する。各項目にプロジェクト名、vault 名、ソースファイルパスを記録する。
3. 結果をフィルタリング: Step 1 のソースと重複排除し、無関係なものを除外。
4. `.linear-refresh/collected-context.json` に `discovery_sources[]` として追記。

## Step 3: Analyze

Cleanup と Add の分析を一括実行する。collected-context.json を1回読み込む。

1. [cleanup-guidelines.md](references/cleanup-guidelines.md) を参照。8カテゴリで変更候補を検出する。
   **`--add-only` 指定時はスキップ。**
2. [add-guidelines.md](references/add-guidelines.md) を参照。`create`/`link`/`skip` の disposition で検出項目を判定する。
   重複排除のため cleanup 結果を参照する。
   **`--cleanup-only` 指定時はスキップ。**
3. `discovery_sources` の項目: 同じ分析を適用するが、根拠にソース別タグを付与する。
   - Slack 由来: `[discovered:slack]`
   - GitHub assigned issues 由来: `[discovered:github]`
   - Obsidian プロジェクトノート由来: `[discovered:obsidian]`
4. **アクティブチケット対話レビュー（description 等が空の項目がある場合のみ）:**
   アクティブチケット（triage / backlog / unstarted / started）のうち、description が空、
   または明らかに文脈が欠落している項目を対象に、`AskUserQuestion` ツールで 1 問ずつ聞く。
   **質問単位:** `description` / `subtasks（親子）` / `relatedTo` / `dueDate` の 4 軸を
   チケット 1 件ずつ順番に提示する（全件まとめて提示しない）。
   **事前コンテキスト収集（質問前に必須）:**
   - タイトル・ラベルから検索キーワードを抽出する。
   - **Obsidian 全 vault** を走査し、タイトル/ラベルに合致するプロジェクトノート・議事録・日報を
     Read して文脈（目的・背景・TODO・関連人物・進行状況）を抽出する。
   - **Slack** を `/slackcli` で検索し、チケットのタイトル・関連キーワードで
     直近30日のメッセージを取得して文脈を抽出する。
   - 2 ソースから得た情報を統合し、description/subtasks の推測案に反映する。
   - コンテキストが見つからない場合はその旨を質問文に明示し、推測案は一般化したものにする。
   **選択肢の生成ルール:**
   - 上記スキャン結果を **ベース** に 2〜3 個の具体的な内容案を組み立て、実際に書き込まれる
     文面をそのまま選択肢の label/description に入れる（ダミー文言禁止）。
   - 必ず `skip`（この項目を更新しない）を選択肢に含める。
   - option 数は tool 仕様上最大 4 なので、推測案 2〜3 + skip で構成する。
   - 「Other」は tool が自動で提供するため明示しない。自由記述で user が代替案を入力可能。
   - multiSelect: false を基本とする（relatedTo のみ multiSelect: true）。
   **順序:** 優先度 High → Medium → Low → No priority の順、同優先度内は state の緊急度順
   （In Progress → Recently To Do → Backlog）。
   **回答の扱い:** すべての回答を `.linear-refresh/plan.json` の該当チケットエントリに
   反映する。選択肢以外の自由記述（Other）が来た場合もそのまま記録する。
5. **セルフチェック:**
   - すべての In Progress チケットが少なくとも1回分析されたか。
   - discovery_sources の deferred signals が Plan に反映されているか。
   - external_sources + discovery_sources の両方が 0 件だがチケットにURLがある場合、異常としてユーザーに報告。
6. `.linear-refresh/plan.json` を書き出す。

## Step 4: Approve

統合 Plan をユーザーに提示して承認を得る。

**`--force` 指定時はスキップ**（Plan は表示するが承認待ちしない）。

表示フォーマット:

```
## Linear Refresh Plan

**Team:** {team_id} ({total_tickets} tickets, {external_sources} linked, {discovery_sources} discovered)

### Cleanup ({N} items)
（カテゴリ別にグループ化: 親子関係、関連、ブロック、ステータス、プロジェクト、コンテキスト、タイトル、期限、重複。空カテゴリは省略。）

### Add ({N} items)
（disposition 別にグループ化: create, link, skip。）

---
Approve? (ok / modify / cancel)
```

- `ok` → Step 5 へ
- ID指定で修正指示 → plan.json を更新し、再提示
- `cancel` → 終了

## Step 5: Execute

承認済み Plan を Linear API で適用する。

1. **Cleanup**（厳密な順序）:
   a. 親子関係の設定（順次実行）
   b. 並列: blockedBy、relatedTo、ステータス変更、プロジェクト紐付け、コンテキスト追加、タイトル変更、期限設定
   c. 重複統合 — Done + duplicateOf（順次実行、最後に実行）
2. **Add**（厳密な順序）:
   a. 新規チケット作成 — **デフォルトステータスは `Backlog`**。Plan で明示的に別ステータスが指定された場合のみ変更する。
   b. 既存チケットへのリンク（コメント + relation/attachment）
3. エラーハンドリング: 個別失敗はスキップして続行、レート制限はリトライ（最大3回）、Cleanup 失敗は Add をブロックしない。
   → 結果フォーマット: [execution-report.md](references/execution-report.md)
4. `.linear-refresh/result.json` を書き出し、結果サマリーを表示する。

## Step 6: Chain（オプション）

後段コマンドを同一セッション内で連続実行する。**両方指定された場合は 6a → 6b の順**。
Slack / GitHub の走査は Step 1-2 で `.linear-refresh/collected-context.json` に収集済みのため、
後段コマンド側で再収集が不要な部分は**キャッシュを参照する前提**で呼び出す（API コール節約）。

### Step 6a: `--project-update` 指定時

影響を受けた PJ ファイルを最新化する。

1. Step 3 の分析で**変更が入ったチケットに紐づくプロジェクト**を集合として抽出する
   （`02_projects/` 配下のどの PJ に属するかは collected-context.json の `linked_projects` で判定）。
2. 各 PJ ディレクトリごとに `/project-update` を invoke する。
   - 入力テキスト: Step 1-2 で収集した Slack / GitHub スニペット（collected-context.json を参照）
   - ユーザー確認ポイントは `/project-update` 側の Step 6 に従う
3. 0 件（該当 PJ なし）の場合はスキップ。実行結果は `.linear-refresh/result.json` の
   `chained.project_update[]` に `{pj, updated_files[]}` で記録する。

### Step 6b: `--daily-log` 指定時

日報へ本日分を集約する。

1. `/daily-log --session --exclude siori --exclude generate-video` を invoke する。
   （除外キーワードは `01_quant/ワークフロー体制.md` の運用ルールに合わせる）
2. `/daily-log` は対象日の日報ファイルが存在しない場合スキップする（新規作成しない仕様）。
3. 実行結果は `.linear-refresh/result.json` の `chained.daily_log` に
   `{status, daily_path}` で記録する。

## Red Flags

**禁止事項:**
- 承認済み Plan なしでの変更実行（`--force` 時を除く）
- チケットの削除・アーカイブ（Cleanup は重複を Close するのみ）
- チケット description の書き換え（コンテキスト追加はコメント/attachment で行う）
- Step 1 での2ホップ超の探索（無限展開防止）
- Step 2 での30日超の検索
- CRUD モードでの `plan.json` / `result.json` への書き込み
- CRUD `--add` でユーザー確認なしの priority=Urgent 設定

**必須事項:**
- Step 1 の前に `/linear-cli` と `/slackcli` を invoke（6-step ワークフローのみ。CRUD では不要）
- 要約予算の遵守（優先度別 200/400/800文字）
- 外部ソースからの deferred signals の記録
- discovery 由来の項目には根拠にソース別タグを付与（`[discovered:slack]` / `[discovered:github]` / `[discovered:obsidian]`）
- すべての実行失敗を result JSON に記録
- CRUD `--done` 実行前にチケットの現在状態を表示すること
- CRUD `--add` で Session Context がある場合は関連付けを提案すること（強制はしない）

## Artifacts

| ファイル | 書き込みステップ | 用途 |
|---------|----------------|------|
| `.linear-refresh/collected-context.json` | Step 1 + Step 2 | 全チケット、リンク済みソース、発見ソース |
| `.linear-refresh/plan.json` | Step 3 | 統合 Cleanup + Add Plan |
| `.linear-refresh/result.json` | Step 5 | 実行結果 |
