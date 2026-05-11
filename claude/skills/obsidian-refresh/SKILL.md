---
name: obsidian-refresh
argument-hint: "[--force] [テキスト入力]"
---

GitHub Issues と `02_projects/` を最新化し、`02_projects/task.md` のタスクを同期する。
`project-update` の機能を統合済み。テキスト入力（議事録・メモ等）があれば `現在の状況` 更新にも使う。

**オプション:**
- `--force`: `02_projects/task.md` の全タスクを再チェック（通常は差分のみ）
- テキスト引数: 議事録・Slack チャット・メモを `現在の状況` 更新の入力として使う

---

## 処理フロー

### Step 1: GitHub Issues 収集

以下を並列取得する:

**GitHub open issues（cmb-sy assigned）:**
```bash
gh api graphql -f query='
{
  search(query: "org:Resily assignee:cmb-sy is:open is:issue", type: ISSUE, first: 100) {
    nodes {
      ... on Issue { number title repository { nameWithOwner } updatedAt url milestone { dueOn } }
    }
  }
}'
```

**`02_projects/task.md` の既存タスク（issue 番号の抽出）:**
```bash
rg -n "Resily/[^#]+#[0-9]+" 02_projects/task.md
```

### Step 2: リポジトリ → プロジェクトセクション マッピング

| GitHub リポジトリ | 02_projects/task.md セクション | 02_projects/ ファイル |
|---|---|---|
| `Resily/data-platform` | `## Data Platform` | `02_projects/ai-task-force/データ基盤構築.md` |
| `Resily/AI-TASKFORCE-auto-EQ-reports-generating` | `## 効果検証活動の自動化` | `02_projects/ai-task-force/効果検証活動の自動化.md` |
| `Resily/AITF` | `## Claude Code 運用` | `02_projects/ai-task-force/claude code運用.md` |
| `Resily/dxp`, `Resily/dxp-visualize-test` | `## DXP-AI解析` | `02_projects/ai-task-force/DXP-AI解析.md`（新規作成可） |
| `Resily/WellCom`, `Resily/WellCom_API` | `## WellCom` | `02_projects/wellcom/index.md`（新規作成可） |
| `Resily/ARM-blog` | **スキップ** | — |
| 上記以外 | `02_projects/_inbox.md` に一時保管 | — |

### Step 3: `02_projects/task.md` のタスク同期

`<!-- BEGIN:tasks -->` 〜 `<!-- END:tasks -->` の範囲のみ操作する。

**3-1. 新規 Issue の追加:**

`02_projects/task.md` 内に同じ issue 番号（`Resily/repo#number` 形式）が存在しない場合のみ、
該当プロジェクトセクションの `### Backlog` 直下に追記する:

```markdown
- [ ] Resily/{repo}#{number} {タイトル}（期日: {milestone.dueOn or 未定}）
```

- **既存タスクは削除しない**（手動追加タスクも保持）
- セクションが存在しない場合は `02_projects/_inbox.md` にフォールバック

**3-2. クローズ済み Issue の更新:**

`02_projects/task.md` 内に `- [ ] Resily/repo#N` 形式で記載されているものについて、
GitHub API で state を確認し closed なら `- [x]` に更新する:
```bash
gh api repos/Resily/{repo}/issues/{number} --jq '.state'
```

更新後、`- [x]` になったタスクを `<!-- BEGIN:done -->` 〜 `<!-- END:done -->` に移動する:
```markdown
- [x] Resily/{repo}#{number} {タイトル} → {YYYY-MM-DD} 完了
```

**3-3. `02_projects/task.md` の frontmatter `updated` を本日日付に更新**

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

マッピング対象外のリポジトリの issue は以下形式で追記:
```markdown
## {YYYY-MM-DD} 未マッピング
- [ ] {repo}#{number} {タイトル} → マッピング先を追加してください
```

### Step 5: 完了報告

```
## obsidian-refresh 完了（{HH:MM}）

02_projects/task.md:
  新規追加: {N}件
    - Data Platform: +{n}件
    - ...
  クローズ更新（- [ ] → - [x]）: {N}件
  Done に移動: {N}件

02_projects/ 更新:
  現在の状況を更新: {N}件
  新規作成: {N}件

スキップ（ARM-blog）: {N}件
未マッピング（_inbox）: {N}件
```

---

## ルール

1. **`02_projects/task.md` の既存タスクは削除しない** — 手動追加タスクを保持する
2. **重複追加しない** — `Resily/repo#number` で照合し、既存行があればスキップ
3. **`<!-- BEGIN:tasks -->` 〜 `<!-- END:tasks -->` の範囲のみ操作する**
4. **Done 移動は `<!-- BEGIN:done -->` 〜 `<!-- END:done -->` に追記**
5. **`02_projects/` の `やること` セクションは触らない** — タスク管理は `02_projects/task.md` に一本化
6. **ARM-blog は常にスキップ**
7. **新規ファイル作成は `dxp` と `wellcom` のみ** — それ以外は `_inbox.md` へ
8. **`gh` コマンドは並列実行可能な部分を並列化してレート制限を回避する**
