---
name: obsidian-refresh
argument-hint: "[--no-push] [--force] [テキスト入力]"
---

`02_projects/task.md` と GitHub Issues を双方向同期し、`02_projects/` を最新化する。

1. **Push（Obsidian → GitHub）**: task.md の完了タスクをクローズ、URLなし新規タスクを Issue 作成
2. **Pull（GitHub → Obsidian）**: GitHub Issues を task.md に反映、02_projects/ の現在の状況を更新

**オプション:**
- `--no-push`: Push をスキップし Pull のみ実行
- `--force`: task.md の全タスクを再チェック（通常は差分のみ）
- テキスト引数: 議事録・Slack チャット・メモを `現在の状況` 更新の入力として使う

---

## リポジトリ ↔ プロジェクトセクション マッピング

| GitHub リポジトリ | 02_projects/task.md セクション | 02_projects/ ファイル |
|---|---|---|
| `Resily/data-platform` | `## Data Platform` | `02_projects/ai-task-force/データ基盤構築.md` |
| `Resily/AI-TASKFORCE-auto-EQ-reports-generating` | `## 効果検証活動の自動化` | `02_projects/ai-task-force/効果検証活動の自動化.md` |
| `Resily/AITF` | `## Claude Code 運用` | `02_projects/ai-task-force/claude code運用.md` |
| `Resily/dxp`, `Resily/dxp-visualize-test` | `## DXP-AI解析` | `02_projects/ai-task-force/DXP-AI解析.md`（新規作成可） |
| `Resily/WellCom`, `Resily/WellCom_API` | `## WellCom` | `02_projects/wellcom/index.md`（新規作成可） |
| `Resily/ARM-blog` | **スキップ** | — |
| 上記以外 | `02_projects/_inbox.md` に一時保管 | — |

---

## 処理フロー

### Step 1: Push — Obsidian → GitHub（`--no-push` 時はスキップ）

task.md を読み込み、以下の2種類を検出する。

**クローズ候補（`- [x]` + GitHub URL あり）:**
- URL から repo・number を抽出し `gh api repos/Resily/{repo}/issues/{number} --jq '.state'` で確認
- すでに `closed` のものはスキップ

**新規 Issue 候補（`- [ ]` + GitHub URL なし）:**
- `<!-- BEGIN:tasks -->` 〜 `<!-- END:tasks -->` 内のみ対象
- **インデント行（行頭がスペース）は対象外** — 手動メモ・解説として保護する
- `http` を含む行は除外
- セクション名からリポジトリを逆引き。マッピングなしの場合はスキップ

検出後、実行計画を提示して `AskUserQuestion` で承認を得る:

```
## obsidian-refresh Push 計画

クローズ（N件）: [タイトル](URL) ...
新規 Issue 作成（N件）: [セクション] タスク本文 ...
スキップ（N件）: 理由 ...

実行しますか？
```

承認後に実行:
- クローズ: `gh issue close {number} --repo Resily/{repo} --comment "Obsidian task.md で完了済みのためクローズ"`
- 新規作成: `gh issue create --repo Resily/{repo} --title "{タイトル}" --assignee cmb-sy --body "Obsidian task.md から作成"`
  → 作成後、task.md の該当行を `- [ ] [{タイトル}]({URL})（期日: 未定）` に書き換える

### Step 2: Pull — GitHub Issues 収集

以下を並列取得する:

**GitHub open issues（cmb-sy assigned）+ sub-issues:**
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

- sub-issues は `state: OPEN` かつ `assignee: cmb-sy` のもののみ追加
- sub-issues は親 issue と同じプロジェクトセクションに追加

**`02_projects/task.md` の既存タスク（URL で重複チェック）:**
```bash
rg -o "https://github\.com/[^)\"']+" 02_projects/task.md
```

### task.md タスクフォーマット

```markdown
- [ ] [{親タイトル}](https://github.com/Resily/{repo}/issues/{number})（期日: {milestone.dueOn or 未定}）
  - [ ] [{サブissueタイトル}](https://github.com/Resily/{repo}/issues/{sub-number})
  - [{サブissueタイトル}](URL)（state: closed）
  - メモや解説テキスト（URL なし・自由記述）
```

- インデント（2スペース）の行はすべて「子要素」として扱い、**自動削除・移動しない**
- 子要素は sub-issue URL、手動メモ、解説いずれでも可

---

### Step 3: task.md のタスク同期

`<!-- BEGIN:tasks -->` 〜 `<!-- END:tasks -->` の範囲のみ操作する。

**3-1. 新規 Issue の追加:**

task.md 内に同じ URL が存在しない（親・子どちらにも）場合のみ追記する。

親 Issue として追記:
```markdown
- [ ] [{タイトル}](https://github.com/Resily/{repo}/issues/{number})（期日: {milestone.dueOn or 未定}）
```

その親 Issue に sub-issues（`state: OPEN` かつ `assignee: cmb-sy`）がある場合、直後にインデントで追記:
```markdown
  - [ ] [{サブissueタイトル}](https://github.com/Resily/{repo}/issues/{sub-number})
```

- 既存タスクは削除しない（手動追加タスク・メモも保持）
- サブセクション（`### 進行中` / `### Backlog` 等）は作成しない
- セクションが存在しない場合は `02_projects/_inbox.md` にフォールバック

**3-2. クローズ済み Issue の更新:**

task.md 内の **トップレベル**（行頭が `- [ ]`）の GitHub URL 付きタスクについて state 確認。
closed なら、そのタスク行とその直下のインデント行（子要素）をまとめて `<!-- BEGIN:done -->` に移動する:
```markdown
- [x] [{タイトル}](https://github.com/Resily/{repo}/issues/{number}) → {YYYY-MM-DD} 完了
  - （子要素もそのまま移動）
```

- インデント行単体（子要素）の state は確認しない（親の完了に従う）

**3-3. frontmatter `updated` を本日日付に更新**

### Step 4: `02_projects/` の現在の状況を更新

各プロジェクトファイルの `### <font color="#81A1C1">現在の状況</font>` セクションを更新する。

**入力ソース（並列取得）:**
- テキスト引数（議事録・メモ等）があればそのまま使う
- 関連 Slack チャンネルを `/slackcli` で検索し直近の文脈を取得
- 関連 GitHub リポジトリの直近コミット・PR を取得

**更新ルール:**
- 更新するセクション: `現在の状況` のみ（方針・やること・未決・関連情報は触らない）
- 入力から読み取れる「直近の動き」を 1〜3 行追記または置換
- 既存内容と矛盾する場合は置換、補足の場合は追記
- frontmatter の `updated` を本日日付に更新
- セクションが存在しない場合はスキップ

**新規ファイルが必要な場合（dxp / wellcom のみ）:**

```markdown
---
title: "{プロジェクト名}"
parent: ai-task-force
updated: {YYYY-MM-DD}
---

### <font color="#81A1C1">現在の状況</font>
（自動生成）

### <font color="#81A1C1">方針・決定事項</font>
（未記入）

### <font color="#81A1C1">やること</font>

### <font color="#81A1C1">未決・課題</font>

### <font color="#81A1C1">関連情報</font>
```

**`02_projects/_inbox.md` へのフォールバック:**

```markdown
## {YYYY-MM-DD} 未マッピング
- [ ] {repo}#{number} {タイトル} → マッピング先を追加してください
```

### Step 5: 完了報告

```
## obsidian-refresh 完了（{HH:MM}）

Push（Obsidian → GitHub）:
  クローズ: {N}件
  新規 Issue 作成: {N}件
  スキップ: {N}件

Pull（GitHub → Obsidian）:
  新規追加: {N}件（Data Platform: +n件 ...）
  クローズ更新（→ Done）: {N}件

02_projects/ 更新:
  現在の状況を更新: {N}件
  新規作成: {N}件
```

---

## ルール

1. **既存タスクは削除しない** — 手動追加タスクを保持する
2. **重複追加しない** — GitHub URL で照合し、既存行があればスキップ
3. **`<!-- BEGIN:tasks -->` 〜 `<!-- END:tasks -->` の範囲のみ操作する**
4. **Done 移動は `<!-- BEGIN:done -->` 〜 `<!-- END:done -->` に追記**
5. **`02_projects/` の `やること` セクションは触らない**
6. **ARM-blog は常にスキップ**
7. **新規ファイル作成は `dxp` と `wellcom` のみ** — それ以外は `_inbox.md` へ
8. **Push の実行は必ずユーザー確認後** — 0件の場合は確認をスキップして Pull へ進む
9. **サブセクションは作成しない**（`### 進行中` / `### Backlog` 等）
10. **インデント行（2スペース以上で始まる行）は保護対象** — sub-issue URL・手動メモ・解説いずれも自動削除しない。Done 移動時は親タスクと一緒に移動する
11. **Push の新規 Issue 候補はトップレベル行のみ** — インデント行は候補にしない
