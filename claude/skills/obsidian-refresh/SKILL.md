---
name: obsidian-refresh
argument-hint: "[--force]"
---

GitHub Issues（cmb-sy に assigned）を収集し、`02_projects/` のプロジェクトファイルを最新化する。Linear の代替として Obsidian を個人タスク管理の正本にする。

**オプション:**
- `--force`: 既存の `やること` セクションを全件再チェック（通常は差分のみ）

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
      ... on Issue { number title repository { nameWithOwner } updatedAt url }
    }
  }
}'
```

**Obsidian 内の既存タスク（issue 番号の抽出）:**
```bash
rg -n "^- \[.\] \`Resily/" 02_projects/ --glob '!_inbox.md'
```

### Step 2: リポジトリ → プロジェクトファイル マッピング

| GitHub リポジトリ | Obsidian ファイル |
|---|---|
| `Resily/data-platform` | `02_projects/ai-task-force/データ基盤構築.md` |
| `Resily/AI-TASKFORCE-auto-EQ-reports-generating` | `02_projects/ai-task-force/効果検証活動の自動化.md` |
| `Resily/AITF` | `02_projects/ai-task-force/claude code運用.md` |
| `Resily/dxp`, `Resily/dxp-visualize-test` | `02_projects/ai-task-force/DXP-AI解析.md`（新規作成可） |
| `Resily/WellCom`, `Resily/WellCom_API` | `02_projects/wellcom/index.md`（新規作成可） |
| `Resily/ARM-blog` | **スキップ**（テックブログ管理のため除外） |
| 上記以外 | `02_projects/_inbox.md` に一時保管 |

### Step 3: 差分更新

各プロジェクトファイルを Read し、以下の操作を行う。

**3-1. 新規 issue の追加:**

`やること` セクション内に同じ issue 番号（`repo#number` 形式）が存在しない場合のみ追記する:

```markdown
- [ ] `Resily/{repo}#{number}` {タイトル}（期日: 未定）
```

追記位置: `### <font color="#81A1C1">やること</font>` の直後（既存 `- [ ]` の前）

**3-2. クローズ済み issue の更新:**

Obsidian 内に `- [ ] \`Resily/repo#N\`` 形式で記載されているものについて、
GitHub API で state を確認し closed なら `- [x]` に更新する:
```bash
gh api repos/Resily/{repo}/issues/{number} --jq '.state'
```

**3-3. frontmatter の `updated` を本日日付に更新**

**3-4. 新規ファイルが必要な場合（dxp / wellcom のみ）:**

以下のテンプレートで作成する:

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

**3-5. `_inbox.md` へのフォールバック:**

マッピング対象外のリポジトリの issue は以下形式で追記:
```markdown
## {YYYY-MM-DD} 未マッピング

- [ ] `{repo}#{number}` {タイトル} → マッピング先を追加してください
```

`_inbox.md` が存在しない場合は新規作成する。

---

### Step 4: 完了報告

```
## obsidian-refresh 完了（{HH:MM}）

新規追加: {N}件
  - 02_projects/ai-task-force/データ基盤構築.md: +{n}件
  - ...

クローズ更新（- [ ] → - [x]）: {N}件

スキップ（ARM-blog）: {N}件
未マッピング（_inbox）: {N}件
```

---

## ルール

1. **`やること` 以外のセクションは触らない** — 現在の状況・方針・未決・関連情報は read-only
2. **重複追加しない** — `repo#number` で照合し、既存行があればスキップ
3. **新規ファイル作成は `dxp` と `wellcom` のみ** — それ以外は `_inbox.md` へ
4. **ARM-blog は常にスキップ** — テックブログ管理用のため個人タスク管理の対象外
5. **Linear 参照（KUNST-xx）はそのまま残す** — 手動でのクリーンアップを妨げない
6. **`gh` コマンドは並列実行可能な部分を並列化してレート制限を回避する**
