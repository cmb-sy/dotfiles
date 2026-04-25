---
name: linear-sync-lite
description: Linear を正本として GitHub Project へ片方向同期する（Level 2）
argument-hint: "[--team KUNST] [--owner cmb-sy] [--project 11] [--repo cmb-sy/kunstSite] [--apply]"
---

Linear を正本（Single Source of Truth）として、GitHub Project へ**片方向同期**する。

## 目的

- Linear のタスク管理を維持したまま、GitHub Project 側の表示を最新化する
- 二重管理を避けるため、**GitHub -> Linear の逆同期は行わない**
- 再実行しても重複を作らない（description のマーカーを利用）

## デフォルト値

- `team`: `KUNST`
- `owner`: `cmb-sy`
- `project`: `11`
- `repo`: `cmb-sy/kunstSite`

引数で上書きがあればそれを優先する。

## 実行モード

- 既定: **dry-run**（計画だけ表示、外部更新なし）
- `--apply` 指定時のみ実際に更新する

---

## 処理フロー

### Step 1: 認証・メタ情報確認

1. `gh auth status` を実行し、`project` scope があることを確認
2. `linear auth whoami` を実行
3. `gh project field-list {project} --owner {owner} --format json` で `Status` フィールドと option を取得
4. 状態マッピングを確定:
   - Linear `started` -> GitHub `In Progress`
   - Linear `completed` / `canceled` -> GitHub `Done`
   - それ以外（`backlog` / `unstarted` / `triage`）-> GitHub の未着手系（`Todo` / `New features` / `Backlog` など）

### Step 2: Linear タスク取得（同期対象）

Linear GraphQL を使って、対象 team の issue を取得する。
**初期運用では完了済み大量流入を防ぐため、`completed` / `canceled` は除外してよい。**

取得項目:
- `identifier`（例: `KUNST-73`）
- `title`
- `url`
- `state.type`
- `description`

### Step 3: 既存リンク判定（重複防止）

各 Linear issue の description を確認:

- `GitHub-Issue: https://github.com/.../issues/{n}` がある -> 既存リンクありとして更新対象にする
- ない -> 新規作成対象

### Step 4: 新規作成（Linear -> GitHub）

`GitHub-Issue` マーカーが無い issue だけ実行:

1. `gh issue create -R {repo} --title "[{IDENTIFIER}] {title}" --body "..."`
2. `gh project item-add {project} --owner {owner} --url {issue_url}`
3. `gh project item-list` で item id を取得
4. `gh project item-edit` で `Status` を Linear 状態に合わせる
5. `linear issue update {IDENTIFIER} --description ...` で以下を追記（既存 description は上書きしない）:

```
GitHub-Issue: https://github.com/{owner}/{repo}/issues/{number}
GitHub-Project: https://github.com/users/{owner}/projects/{project}
```

### Step 5: 既存リンクの状態同期（片方向）

`GitHub-Issue` マーカーがある issue について:

1. GitHub 側の project item を特定
2. `Status` が Linear 状態と異なる場合のみ更新
3. タイトルは原則変更しない

### Step 6: 完了報告

- 同期対象 issue 数
- 新規作成数（GitHub Issue / Project item）
- 状態更新数
- スキップ数（理由付き）
- dry-run / apply の別

---

## 重要ルール

1. **逆同期禁止**: GitHub 側の変更で Linear 状態を更新しない
2. **重複作成禁止**: `GitHub-Issue:` マーカーがあるものは新規作成しない
3. **安全運用**: 初回は必ず dry-run、ユーザー確認後に `--apply`
4. **大量作成ガード**: 1回の実行で新規作成は最大20件まで。超える場合は打ち切って確認する
5. **description 保全**: 既存本文を消さない。追記のみ

---

## 推奨運用

- 日次: `/linear-sync-lite`（dry-run）-> 問題なければ `/linear-sync-lite --apply`
- 週次: `/linear-refresh` で棚卸し（重い処理）
