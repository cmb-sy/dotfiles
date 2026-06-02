---
name: github-issues
description: >-
  `gh` CLI による GitHub Issue 操作（一覧・作成・更新・クローズ・コメント）。
  Obsidian/ファイル連携は持たない、純粋な issue 管理スキル。
argument-hint: "list | create | close <number> | comment <number> | update <number> [自然言語の指示]"
user-invocable: true
---

`gh` CLI を使って GitHub Issue を操作する。ファイル I/O・Obsidian 連携は一切持たない（純粋な issue 操作のみ）。

**対象組織:** `Resily`（デフォルト assignee は `cmb-sy`）。リポジトリは引数または文脈から特定する。

---

## 操作の判定（エントリ）

| 状況 | 動作 |
|---|---|
| **引数なし** | `AskUserQuestion`（header: `操作`）で操作を選ばせる: `新規作成` / `更新` / `クローズ` / `コメント` / `一覧`。選択後に該当サブコマンドへ進む |
| 引数の先頭語が `list`/`create`/`update`/`close`/`comment` | その操作へ直行 |
| 自然言語（「一覧」「作成」「更新」「閉じる」「コメント」等） | 意図から操作を判定して直行 |

操作が引数・文脈から自明な場合は操作選択の質問を省略する。

| 操作 | トリガー | 動作 |
|---|---|---|
| `list` | `list` / 「一覧」「open な issue」 | open issue を一覧表示 |
| `create` | `create` / 「作成」「新しい issue」 | 新規 issue を作成 |
| `update` | `update <number>` / 「更新」「タイトル変更」 | 既存 issue を編集 |
| `close` | `close <number>` / 「クローズ」「閉じる」 | issue をクローズ |
| `comment` | `comment <number>` / 「コメント」 | issue にコメント追加 |

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

### Step 6: 担当者・期日の選択

`AskUserQuestion` で **2 問まとめて**聞く:

- **担当者**（header: `担当者`）: 候補は **Step 5 で取得した repo の collaborators（登録メンバー）だけ**に限定する。推測で人名を足さない。bot（`Resilybot` 等）は除外する。`multiSelect: true`（複数アサイン可）
  - collaborators が AskUserQuestion の選択肢上限（4）以下なら全員を選択肢に出す
  - 5 名以上いる場合は、**全 collaborators を role 付きでテキスト一覧提示**し、ユーザーに login を指定してもらう（選択肢には `自分(cmb-sy)` + 数名を出し、残りは `Other` で login 指定）。`Other` で渡される login も collaborators であることを前提とする
- **期日**（header: `期日`）: 選択肢を以下で出す。milestone が存在すれば milestone も候補に加える:
  - `今週中`（今週金曜）/ `今月末` / `期日なし` / 既存 milestone 名（あれば）
  - `Other` で `YYYY-MM-DD` 直接指定も受ける

**期日の反映方法:**
- 既存 milestone を選んだ場合 → `--milestone "{title}"` を付与
- 日付（今週中/今月末/カスタム）を選んだ場合 → GitHub issue に期日フィールドは無いため、**本文末尾に `期日: YYYY-MM-DD` 行を追記**する（`date -v` で絶対日付に変換）
- `期日なし` → 何もしない

### Step 7: 最終確認と作成

確定した repo / title / body / assignee / 期日 をまとめて提示し、最終確認を取る。承認後に実行:

```bash
gh issue create --repo Resily/{repo} \
  --title "{タイトル}" \
  --body "{洗練した本文}" \
  --assignee {login1} [--assignee {login2}] \
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

### Step 8: リンク返却

作成された issue の **URL を必ず報告する**（`gh issue create` の標準出力に URL が返る）。
`#{number} {タイトル} → {URL}` 形式で出し、**AITF ボードへ追加した旨も添える**。

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

## ルール

1. **ファイル I/O を行わない** — ローカルファイルの読み書き・Obsidian 連携は一切しない
2. **破壊的/外部可視の操作は実行前に確認** — create / close / comment / update。list は確認不要
3. **デフォルト assignee は `cmb-sy`**、組織は `Resily`
4. **PII を body/comment に転記しない** — Slack 本文や同僚名等はマスキング、または含めない
5. **リポジトリが特定できない場合は推測せず確認する**
6. **実行後は issue 番号と URL を報告する**
7. **create した issue は必ず AITF ボード（project 26）に追加する** — `gh project item-add 26 --owner Resily --url {URL}`
