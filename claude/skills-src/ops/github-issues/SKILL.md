---
name: github-issues
description: >-
  GitHub Issue を一覧・作成・更新・クローズ・コメントしたいとき、および PR 作成+Projects 登録を
  一気通貫で行いたいときに使う `gh` CLI ベースのスキル。対象組織は Resily、デフォルト assignee は cmb-sy。
  ファイル I/O・Obsidian 連携は持たない。旧 github-ops を吸収（pr サブコマンド）。
argument-hint: "list | create | close <number> | comment <number> | update <number> | pr [--content <text>] [--project <number>] [--draft] [--skip-project] [自然言語の指示]"
user-invocable: true
---

`gh` CLI を使って GitHub Issue を操作する。ファイル I/O・Obsidian 連携は一切持たない（純粋な issue 操作のみ）。

**対象組織:** `Resily`（デフォルト assignee は `cmb-sy`）。リポジトリは引数または文脈から特定する。

---

## 操作の判定（エントリ）

**引数なしの場合**は `AskUserQuestion`（header: `操作`）で `新規作成` / `更新` / `クローズ` / `コメント` / `一覧` を選ばせてから該当操作へ進む。**引数の先頭語または自然言語で操作が自明な場合**は質問を省略して直行する。

| 操作 | トリガー（先頭語 / 自然言語） | 動作 |
|---|---|---|
| `list` | `list` / 「一覧」「open な issue」 | open issue を一覧表示 |
| `create` | `create` / 「作成」「新しい issue」 | 新規 issue を作成 |
| `update` | `update <number>` / 「更新」「タイトル変更」 | 既存 issue を編集 |
| `close` | `close <number>` / 「クローズ」「閉じる」 | issue をクローズ |
| `comment` | `comment <number>` / 「コメント」 | issue にコメント追加 |
| `pr` | `pr` / 「PR 作成」「プルリク」「Projects 登録」 | PR 作成 + GitHub Projects 登録（旧 github-ops） |

破壊的・外部可視の操作（create / close / comment / update）は、**実行前に内容を提示してユーザー確認を取る**。list は確認不要。

---

## list — 一覧

`cmb-sy` にアサインされた open issue を組織横断で取得し、sub-issue も含めて表示する。

```bash
gh api graphql -f query='
{
  search(query: "org:Resily assignee:cmb-sy is:open is:issue", type: ISSUE, first: 100) {
    nodes {
      ... on Issue {
        number title url
        repository { nameWithOwner }
        milestone { dueOn }
        subIssues(first: 50) {
          nodes {
            number title url state
            assignees(first: 5) { nodes { login } }
            repository { nameWithOwner }
            milestone { dueOn }
          }
        }
      }
    }
  }
}'
```

- sub-issue は `state: OPEN` かつ `assignee: cmb-sy` のもののみ表示
- リポジトリ単位でグルーピングし、`#{number} {タイトル}（期日: {milestone.dueOn or 未定}）` 形式で出す
- 特定リポジトリに絞る場合: `gh issue list --repo Resily/{repo} --assignee cmb-sy --state open`

引数で検索条件が渡された場合（例: ラベル・キーワード）は GraphQL の `search` クエリに反映する。

---

## create — 作成

「何を」「どのプロジェクトで」を最初にユーザーから受け取り、**そのプロジェクトの既存 issue・実装状態を確認したうえで**下書きを洗練し、担当者・期日を選択肢で確定して作成、最後に **issue の URL を返す**。対話型フロー。

### Step 1: 内容とプロジェクトのヒアリング

まずユーザーに **2 つ**を尋ねる（引数で既に渡っていればその分はスキップ）:

1. **issue 内容**: 何をしたいか（雑なメモ・箇条書き・口語で可）
2. **どのプロジェクトのものか**: repo を特定するための手がかり

issue 内容が未入力なら「どんな issue を作りますか（内容と対象プロジェクトを教えてください）」と促す。プロジェクトが曖昧なら Step 2 の選択肢で確定する。

### Step 2: プロジェクト（repo）の特定

入力内容・プロジェクト名から repo を特定する。下記マッピングを優先し、判別できなければ `AskUserQuestion`（header: `プロジェクト`、`Other` で自由入力可）で確認する:

| 選択肢ラベル | repo |
|---|---|
| Data Platform | `Resily/data-platform` |
| 効果検証自動化 | `Resily/AI-TASKFORCE-auto-EQ-reports-generating` |
| Claude Code 運用 | `Resily/arm-claude-code` |
| DXP-AI解析 | `Resily/dxp` |
| WellCom | `Resily/WellCom` |

推測で repo を確定しない。確信が持てなければ必ず確認する。

### Step 3: プロジェクトの状態確認（**洗練の前に必須**）

repo 確定後、作成前に **その repo の既存タスクと実装状態を確認**する。重複 issue の回避・文脈に沿った記述・関連 issue へのリンクのために行う。

```bash
# 既存 open issue（重複・関連チェック）
gh issue list --repo Resily/{repo} --state open --limit 50 --json number,title,url,labels
# 直近の実装状態（コミット・PR の動き）
gh api "repos/Resily/{repo}/commits?per_page=10" --jq '.[].commit.message' 2>/dev/null | head -10
gh pr list --repo Resily/{repo} --state all --limit 10 --json number,title,state,url
```

確認結果から:
- **重複候補**があれば、新規作成せず既存 issue を提示して「更新/コメントで対応するか、別物として新規作成するか」をユーザーに確認する
- 関連する既存 issue があれば、本文に `関連: #{number}` として参照を入れる
- 直近のコミット/PR から読み取れる実装状況を踏まえ、本文の前提・スコープを調整する

### Step 4: 下書きの洗練と擦り合わせ（**反復**）

Step 1 の入力を、Step 3 で得た文脈を踏まえて GitHub issue 形に整える。

- **タイトル**: 1 行で要点を表す簡潔な命令形/体言止め（例: 「データ基盤の retry 処理を指数バックオフ化」）
- **本文**: 入力から読み取れる範囲で以下を補う（情報が無い項目は省略、捏造しない）:
  - 背景・目的
  - やること（チェックリスト `- [ ]` 可）
  - 完了条件（あれば）
  - 関連 issue / リンク（Step 3 で見つかった関連先・入力に含まれるもの）
- 入力に無い事実・数値・固有名を**勝手に足さない**。曖昧な点は本文に `（要確認）` と残すか確認する
- PII（同僚名・社員番号・Slack 本文等）は body に転記しない。必要なら一般化・マスキングする

洗練した **タイトル + 本文のドラフト**をユーザーに提示する。

**擦り合わせ（ここで一度立ち止まり、ユーザーと反復する）:**

入力（特に口語・連絡文・メモ）を issue 化すると、解釈の **ズレ・ノイズ**が入りやすい。ドラフト提示時に、解釈が割れうる箇所を**自分から具体的に指摘**し、ユーザーの確認・修正を受けて作り直す。承認が出るまで Step 5 へ進まない。

典型的に確認すべきズレ:
- **宛先・目的**: 相手への「依頼」か、自分用の「todo/トラッキング」か。assignee が自分なのに本文が「〜してください」依頼調だと不整合。書き分ける
- **依頼 vs 状況共有**: 「〜までに連絡します」等は依頼ではなく予告・状況メモ。チェック項目にせず注記にする
- **項目の性質の混同**: 識別子（ID）と指標、手段と目的などを安易にひとくくりにしない
- **1 issue か分割か**: 性質や担当者が異なる複数の論点が混在していたら、分割を提案する
- **元文の丁寧語・前置き・謝辞**（「お忙しいところ恐れ入りますが」等）は issue では削ぎ、要点だけ残す

指摘は「私の解釈ではこうだが、合っているか」と提示し、ユーザーの回答で本文を更新する。複数回やり取りしてよい。**ユーザーが内容に合意してから** Step 5 に進む。

### Step 5: 担当者・期日の候補取得

確定した repo に対して担当者候補と milestone を取得する。**担当者候補は `collaborators`（その repo の登録メンバー）だけを使う。** `assignees` エンドポイントや org メンバーは広く出すぎるため使わない。推測で login を足さない。

```bash
# repo の collaborators（登録メンバー）= 担当者候補。bot は除外
gh api "repos/Resily/{repo}/collaborators" --jq '.[] | "\(.login)\t(\(.role_name))"'
# 期日付き milestone 一覧（open）
gh api "repos/Resily/{repo}/milestones?state=open" --jq '.[] | "\(.title)\t\(.due_on // "期日なし")"'
```

### Step 5b: ラベル・タイプ・優先度/サイズの候補取得

**Issue には常にラベル・タイプ・（Project ボードの）優先度/サイズを設定する。** 該当する既存の値が無ければ、その場で新規作成する（後述）。

```bash
# 既存ラベル一覧
gh label list --repo Resily/{repo}
# 既存 Issue Type 一覧（org 単位で定義され、repo に対して有効化されているもの）
gh api graphql -f query='
{
  repository(owner: "Resily", name: "{repo}") {
    issueTypes(first: 20) { nodes { id name description isEnabled } }
  }
}'
```

優先度（Priority）・サイズ（Size）は AITF ボード（project 26）の固定フィールドを使う（値は既知、再取得不要）:

| フィールド | field-id | 選択肢 |
|---|---|---|
| Priority | `PVTSSF_lADOArEsis4BIUQAzg4z9-k` | P0(`79628723`) / P1(`0a877460`) / P2(`da944a9c`) |
| Size | `PVTSSF_lADOArEsis4BIUQAzg4z9-o` | XS(`6c6483d2`) / S(`f784b110`) / M(`7515a9f1`) / L(`817d0097`) / XL(`db339eb2`) |

他のボードに追加する場合（project 26 以外）は、都度 `gh api graphql` で当該 project の `fields` を問い合わせて field-id・option-id を取得し直す（ハードコードしない）。

### Step 6: 担当者・期日の選択

`AskUserQuestion` で **2 問まとめて**聞く:

- **担当者**（header: `担当者`）: 候補は **Step 5 で取得した repo の collaborators（登録メンバー）だけ**に限定する。推測で人名を足さない。bot（`Resilybot` 等）は除外する。`multiSelect: true`（複数アサイン可）
  - collaborators が AskUserQuestion の選択肢上限（4）以下なら全員を選択肢に出す
  - 5 名以上いる場合は、**全 collaborators を role 付きでテキスト一覧提示**し、ユーザーに login を指定してもらう（選択肢には `自分(cmb-sy)` + 数名を出し、残りは `Other` で login 指定）。`Other` で渡される login も collaborators であることを前提とする
- **期日**（header: `期日`）: 選択肢を以下で出す。milestone が存在すれば milestone も候補に加える:
  - `今週中`（今週金曜）/ `今月末` / `期日なし` / 既存 milestone 名（あれば）
  - `Other` で `YYYY-MM-DD` 直接指定も受ける

**期日の反映方法（ユーザーが明確な期限を述べている場合を優先する）:**
- ユーザーが「〜までに」「〜日締切」等、**具体的な期限を明言している場合** → まず既存 milestone（Step 5 で取得済み）に `due_on` が一致するものが無いか確認する
  - 一致する既存 milestone がある → それを使う（`--milestone "{title}"`）
  - 一致するものが無い → **その場で新規作成する**（下記コマンド）。タイトルは日付か内容から簡潔に付ける（例: `2026-07-22 締切分`）
    ```bash
    gh api repos/Resily/{repo}/milestones -f title="{title}" -f due_on="{YYYY-MM-DD}T00:00:00Z" -f state=open
    ```
  - 作成した milestone も `--milestone "{title}"` で issue に付与する
- ユーザーが期限を明言していない、かつ「今週中」「今月末」等の相対表現のみの場合 → 既存の運用どおり、本文末尾に `期日: YYYY-MM-DD` 行を追記する（`date -v` で絶対日付に変換）。milestone は新規作成しない
- `期日なし` → 何もしない

### Step 6b: ラベル・タイプの選択

`AskUserQuestion` で **2 問まとめて**聞く:

- **ラベル**（header: `ラベル`）: 候補は Step 5b で取得した既存ラベルから、内容に合いそうなものを提示する（`multiSelect: true`）。合うものが無ければ `Other` で新規ラベル名を受け付け、以下で作成してから使う:
  ```bash
  gh label create "{name}" --repo Resily/{repo} --description "{説明}" --color "{6桁hex、指定なければ ededed}"
  ```
- **タイプ**（header: `タイプ`）: 候補は Step 5b で取得した既存 Issue Type（例: Task / Bug / Feature）。内容から最も自然なものを一番上に推奨として出す。合うものが無ければ `Other` で新規タイプ名を受け付け、以下で作成する（**org 管理者権限が必要な場合がある**。権限エラーになったら「既存タイプで代用するか、権限のある人に作成を依頼してください」と案内し、既存タイプへのフォールバックを提案する）:
  ```bash
  ORG_ID=$(gh api graphql -f query='{ organization(login: "Resily") { id } }' --jq '.data.organization.id')
  gh api graphql -f query='
  mutation($ownerId: ID!, $name: String!, $description: String) {
    createIssueType(input: {ownerId: $ownerId, name: $name, description: $description, isEnabled: true}) {
      issueType { id name }
    }
  }' -f ownerId="$ORG_ID" -f name="{name}" -f description="{説明}"
  ```

### Step 6c: 優先度・サイズの選択

`AskUserQuestion` で **2 問まとめて**聞く（header: `優先度` / `サイズ`）。選択肢は Step 5b の Priority(P0/P1/P2) / Size(XS/S/M/L/XL)。**「未設定」も選択肢に含める**（すべての issue に無理に優先度・サイズを付けない。判断材料が無ければ未設定を推奨として出す）。

### Step 7: 最終確認と作成

確定した repo / title / body / assignee / 期日 / ラベル / タイプ / 優先度 / サイズ をまとめて提示し、最終確認を取る。承認後に実行:

```bash
gh issue create --repo Resily/{repo} \
  --title "{タイトル}" \
  --body "{洗練した本文}" \
  --assignee {login1} [--assignee {login2}] \
  [--label "{label1}"] [--label "{label2}"] \
  [--milestone "{title}"]
```

### Step 7b: プロジェクトボードへの追加（必須）

`gh issue create` で作成した issue はプロジェクトボードに自動では載らない。さらに、追加直後の Status は **`Done`** になりボードのデフォルトビューから隠れてしまうため、**追加 + Status を `Backlog` に設定するまでをセットで実行する**。

```bash
# 1) AITF ボード（project 26）に追加し、item id を取得
ITEM_ID=$(gh project item-add 26 --owner Resily --url {作成された issue の URL} --format json --jq '.id')

# 2) Status を Backlog に設定（追加直後は Done で隠れるため必須）
gh project item-edit \
  --id "$ITEM_ID" \
  --project-id PVT_kwDOArEsis4BIUQA \
  --field-id PVTSSF_lADOArEsis4BIUQAzg4z98s \
  --single-select-option-id f75ad846
```

- project 26 = AITF ボード。`projectId=PVT_kwDOArEsis4BIUQA`、Status フィールド `PVTSSF_lADOArEsis4BIUQAzg4z98s`、`Backlog` オプション `f75ad846`
- Status オプション: Backlog `f75ad846` / Ready `61e4505c` / In progress `47fc9ee4` / In review `df73e18b` / Done `98236657`
- これは org の共有ボードを変更する操作だが、運用上 create とセットで常に実行する（ユーザーの恒久指示）
- 失敗した場合（権限・project scope 不足など）はエラーを報告し、手動追加を案内する

### Step 7c: Issue Type の設定

`gh issue create` に issue type を直接渡すフラグは無いため、作成後に GraphQL で設定する。Step 6b で選んだタイプが「無し」でない限り必ず実行する。

```bash
ISSUE_NODE_ID=$(gh issue view {number} --repo Resily/{repo} --json id --jq .id)
gh api graphql -f query='
mutation($issueId: ID!, $typeId: ID!) {
  updateIssue(input: {id: $issueId, issueTypeId: $typeId}) {
    issue { id issueType { name } }
  }
}' -f issueId="$ISSUE_NODE_ID" -f typeId="{Step 6b で確定した type の node id}"
```

失敗した場合はエラーを報告し、タイプ無しのまま続行してよいか確認する。

### Step 7d: 優先度・サイズの設定

Step 6c で「未設定」以外を選んだ場合、Step 7b で取得した `$ITEM_ID` に対して同じ project item-edit パターンで設定する。

```bash
# 優先度
gh project item-edit --id "$ITEM_ID" --project-id PVT_kwDOArEsis4BIUQA \
  --field-id PVTSSF_lADOArEsis4BIUQAzg4z9-k --single-select-option-id "{選んだ Priority の option-id}"
# サイズ
gh project item-edit --id "$ITEM_ID" --project-id PVT_kwDOArEsis4BIUQA \
  --field-id PVTSSF_lADOArEsis4BIUQAzg4z9-o --single-select-option-id "{選んだ Size の option-id}"
```

### Step 8: リンク返却

作成された issue の **URL を必ず報告する**（`gh issue create` の標準出力に URL が返る）。
`#{number} {タイトル} → {URL}` 形式で出し、**AITF ボードへ追加した旨、設定したラベル・タイプ・優先度・サイズ・milestone（新規作成した場合はその旨）も添える**。

---

## update — 更新

既存 issue を編集する。number は必須。

```bash
gh issue edit {number} --repo Resily/{repo} [--title "..."] [--body "..."] [--add-label "..."] [--remove-label "..."] [--add-assignee "..."] [--milestone "..."]
```

- 変更点のみフラグを付ける（無指定の項目は変更しない）
- 変更内容を提示して確認後に実行

---

## close — クローズ

```bash
gh issue close {number} --repo Resily/{repo} [--comment "{理由}"] [--reason completed|not planned]
```

- クローズ理由のコメントがあれば `--comment` で付与
- 対象 issue のタイトルを提示して確認後に実行

---

## comment — コメント

```bash
gh issue comment {number} --repo Resily/{repo} --body "{本文}"
```

- 投稿内容を提示して確認後に実行

---

## pr — PR 作成 + Projects 登録（旧 github-ops）

セッションコンテキストまたは `--content <text>` から PR を構成して作成/更新し、選んだ GitHub Project にアイテム登録する。既存アイテムには対話的操作（ステータス変更/サブタスク/コメント/DONE）を提供する。

**フラグ:** `--content <text>`（フリーテキストから PR 構成）/ `--project <number>`（Project 直接指定）/ `--draft` / `--skip-project`（PR 作成のみ）

**前提:** `gh auth status` で認証と `project` スコープを確認（未付与なら「`gh auth refresh -s project` を実行してください」と案内して終了）。Git リポジトリ内・リモート設定済みであること。

### pr Phase 1: Context Collection

- 並列取得: 現在ブランチ / `git log --oneline main..HEAD` / `git diff main...HEAD --stat` / `git remote get-url origin` / `gh pr list --head {branch} --json number,title,url,state --limit 5`
- ベースブランチ推定: `git config branch.{branch}.gh-merge-base` → `git symbolic-ref refs/remotes/origin/HEAD --short` → フォールバック `main`
- handover が保存した `project-state.json` / `handover.md` が現在ブランチ向けに存在すれば Read し、done タスク・decisions・session_notes を抽出（保存先は handover skill 準拠）
- コンテンツソース優先順: `--content` > project-state.json > 直近コミットメッセージ（`git log --format='%s%n%b' HEAD~5..HEAD`）

### pr Phase 2: PR Resolution

`gh pr list` の結果で分岐: 既存なし/closed/merged → 新規作成へ。open の PR あり → AskUserQuestion で「既存を更新（推奨）/ 新規作成 / PR 操作スキップ（Projects のみ）/ キャンセル」。

### pr Phase 3: PR Execution

- **Title**: 70文字以内。project-state.json があれば Pipeline 名+主要タスク要約、`--content` ならその1行要約、フォールバックは最新コミット1行目
- **Body**: `## Summary`(1-3行) / `## Changes`(diff --stat) / `## Context`(decisions・session_notes または --content またはコミット body) / `## Test Plan`(test_results なければ `- [ ] Manual verification required`)
- **プレビュー承認必須**: Title/Base/Head/Draft/Body 先頭200字を提示し AskUserQuestion で承認を取ってから実行。修正は Other で受ける
- 新規: `git push -u origin {branch}`(未 push 時) → `gh pr create --title ... --body ... --base {base} --assignee "@me" [--draft]`。更新: `git push` → `gh pr edit {number} --title ... --body ...`
- push 失敗時は AskUserQuestion:「`--force-with-lease` 再 push(main/master は拒否) / `git pull --rebase` → 再 push / キャンセル」

### pr Phase 4: Project Registration

`--skip-project` 時はスキップ。

1. `--project <N>` 指定があればそれ、なければ `gh project list --owner @me --format json` から AskUserQuestion で選択（スキップ選択肢を含める）
2. `gh project item-list {N} --owner @me --format json --limit 100` で PR URL 照合（多ければ limit を 100→300→全件と拡大）
3. 未登録 → `gh project item-add {N} --owner @me --url {pr_url}`
4. 登録済み → ループ形式で対話操作: ステータス変更（`field-list` で Status 選択肢取得 → `item-edit`）/ サブタスク追加（`item-create --title ... --body "Parent: #{pr}"`）/ PR コメント / DONE 化。「完了」選択で抜ける

### pr Phase 5: Report

作成/更新した PR の番号・URL・状態と、Project へのアクション（登録/変更/スキップ）を報告する。

### pr のエラー処理

issue 系と共通（未認証・リポジトリ外・リモート未設定は案内して終了）に加え: detached HEAD → ブランチ名を確認 / `gh pr create`・`item-add` 失敗 → エラー表示しリトライ確認（最大2回）/ Project 0件 → 報告してスキップ / API レート制限 → 30秒待機リトライ（最大3回）。

### pr の Red Flags

- ユーザー承認なしの PR 作成/更新/Project 操作
- main/master への force push（対話でも拒否）
- PR body へのシークレット転記、project-state.json 全文コピー（要約して使う）
- 既存 PR チェック（Phase 2）・既存アイテムチェック（Phase 4）のスキップ

---

## ルール

1. **ファイル I/O を行わない** — ローカルファイルの読み書き・Obsidian 連携は一切しない
2. **破壊的/外部可視の操作は実行前に確認** — create / close / comment / update。list は確認不要
3. **デフォルト assignee は `cmb-sy`**、組織は `Resily`
4. **PII を body/comment に転記しない** — Slack 本文や同僚名等はマスキング、または含めない
5. **リポジトリが特定できない場合は推測せず確認する**
6. **実行後は issue 番号と URL を報告する**
7. **create した issue は必ず AITF ボード（project 26）に追加し、Status を `Backlog` に設定する** — 手順・フィールド ID は Step 7b を参照（追加直後の Status は `Done` になり隠れるため Backlog 設定まで必須）
8. **create した issue には必ずラベル・タイプ・優先度/サイズを設定する** — 該当する既存の値が無ければ、確認せずその場で新規作成する（ラベル: `gh label create`、タイプ: `createIssueType` GraphQL mutation。タイプ新規作成が権限不足で失敗した場合のみ、既存タイプへのフォールバックを確認する）。優先度・サイズは「未設定」も正当な選択肢とする
9. **ユーザーが具体的な期限を明言した場合、その期限に対応する milestone を使う** — 既存 milestone に一致する `due_on` が無ければ、確認せずその場で新規作成し issue に付与する。期限の明言が無い相対表現（今週中/今月末）のみの場合は、従来どおり本文への期日追記に留め milestone は作成しない
10. **一度確立したこれらの標準動作（ラベル・タイプ・フィールド・milestone の自動補完）は、以後のすべての create 操作に適用する** — 個別の issue ごとに毎回確認を求めない
