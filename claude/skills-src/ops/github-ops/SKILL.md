---
name: github-ops
description: >-
  PR 作成と GitHub Projects への登録を一気通貫で行いたいときに使うスキル。
  セッションコンテキストまたはフリーテキストから PR を構成し、ランタイムで選んだ Project にアイテムを登録する。
  既存アイテムには対話的にステータス変更・サブタスク追加・DONE 操作を提供する。フラグの詳細は本文の Options を参照。
argument-hint: "[--content <text>] [--project <number>] [--draft] [--skip-project]"
user-invocable: true
---

# GitHub Ops

PR 作成と GitHub Projects 登録を一気通貫で実行する。

## Options

| Option | 効果 |
|--------|------|
| `--content <text>` | フリーテキストから PR title/body を構成（セッションコンテキストの代わり） |
| `--project <number>` | Project 番号を直接指定（ランタイム選択をスキップ） |
| `--draft` | PR を Draft として作成 |
| `--skip-project` | Project 登録をスキップ（PR 作成のみ） |

## Prerequisites

1. `gh` CLI が利用可能であること: `which gh`
2. 認証状態: `gh auth status`
3. `project` スコープが付与されていること: `gh auth status` の出力で確認。
   未付与の場合 → 「`gh auth refresh -s project` を実行してください」と案内して終了
4. Git リポジトリ内であること: `git rev-parse --is-inside-work-tree`
5. リモートが設定されていること: `git remote -v` で確認

## Workflow

```
Phase 1: Context Collection   — branch / diff / session state を収集
Phase 2: PR Resolution        — 既存 PR の有無を判定、作成 or 更新を決定
Phase 3: PR Execution         — プレビュー → 承認 → push → PR 作成/更新
Phase 4: Project Registration — Project 選択 → 登録 or 既存アイテム対話操作
Phase 5: Report               — 実行結果の表示
```

**開始時アナウンス:** 「GitHub Ops を開始します。Phase 1: Context Collection」

## Phase 1: Context Collection

セッションコンテキストと Git 状態を収集する。

### 1a. Git 状態の収集（並列実行）

- `git rev-parse --abbrev-ref HEAD` → 現在のブランチ名
- `git log --oneline main..HEAD` → ブランチ上のコミット
- `git diff main...HEAD --stat` → 変更ファイル一覧
- `git remote get-url origin` → リポジトリの owner/repo を特定
- `gh pr list --head $(git rev-parse --abbrev-ref HEAD) --json number,title,url,state,projectItems --limit 5` → 既存 PR

ベースブランチの推定:
1. `git config branch.{branch}.gh-merge-base`
2. `git symbolic-ref refs/remotes/origin/HEAD --short`
3. フォールバック: `main`

### 1b. セッション状態の収集（任意）

1. `.agents/handover/` 配下に現在ブランチの READY セッションが存在するか確認
2. 存在する場合 → `project-state.json` を Read
   - `active_tasks[]` の done タスクの説明・commit_sha を抽出
   - `recent_decisions[]` を抽出
   - `pipeline` フィールドがあれば Pipeline 名とフェーズ進行状況を抽出
   - `session_notes[]` から insight/directive を抽出
3. `handover.md` が存在する場合 → 補足コンテキストとして Read

### 1c. コンテンツソースの決定

| 条件 | ソース |
|------|--------|
| `--content <text>` 指定 | フリーテキスト入力を PR body のベースにする |
| project-state.json 存在 | done タスク + decisions + session_notes から構成 |
| どちらも不在 | `git log --format='%s%n%b' HEAD~5..HEAD` のコミットメッセージから構成 |

## Phase 2: PR Resolution

既存 PR の有無を判定し、作成 or 更新を決定する。

### 判定ロジック

Phase 1a の `gh pr list` の結果に基づく:

| 既存 PR | 状態 | アクション |
|---------|------|-----------|
| なし | — | Phase 3: 新規作成 |
| あり | open | AskUserQuestion で選択肢を提示 |
| あり | closed/merged | Phase 3: 新規作成（既存は無視） |

### 既存 PR が open の場合の対話

AskUserQuestion:

```
ブランチ `{branch}` に既存の PR があります:
  #{number} {title} ({state})
  {url}

どうしますか？
1. [推奨] 既存 PR を更新（title/body の上書き）
2. 新規 PR を作成（既存 PR はそのまま）
3. PR 操作をスキップし、Project 登録のみ実行
4. キャンセル
```

## Phase 3: PR Execution

PR を作成 or 更新する。

### 3a. PR title/body の生成

**Title ルール:**
- 70文字以内
- project-state.json がある場合: Pipeline 名 + 主要タスクの要約
- `--content` 指定時: テキストの1行要約
- フォールバック: 最新コミットメッセージの1行目

**Body テンプレート:**

```markdown
## Summary
<!-- Phase 1c のソースに基づく 1-3 行の要約 -->

## Changes
<!-- git diff --stat のファイル一覧 -->

## Context
<!-- project-state.json の decisions/session_notes、
     または --content テキスト、
     またはコミットメッセージの body -->

## Test Plan
<!-- project-state.json に test_results があれば記載、
     なければ "- [ ] Manual verification required" -->
```

### 3b. プレビューと承認

AskUserQuestion で PR プレビューを提示:

```
## PR プレビュー
- Title: {title}
- Base: {base_branch}
- Head: {current_branch}
- Draft: {yes/no}
- Body: {body の先頭200文字}...

この内容で PR を作成しますか？
1. [推奨] OK
2. キャンセル
```

修正があれば Other で指示を受け付ける。

### 3c. Push と PR 作成/更新

**新規作成モード:**
1. `git push -u origin {branch}`（未プッシュの場合のみ）
2. PR 作成:
   ```bash
   gh pr create --title "{title}" --body "$(cat <<'EOF'
   {body}
   EOF
   )" --base "{base_branch}" --assignee "@me" {--draft}
   ```
3. PR URL を保持

**更新モード:**
1. `git push`
2. PR 更新:
   ```bash
   gh pr edit {number} --title "{title}" --body "$(cat <<'EOF'
   {body}
   EOF
   )"
   ```

### 3d. Push 失敗時

AskUserQuestion:
1. `--force-with-lease` で再 push（main/master の場合は拒否）
2. `git pull --rebase` → 再 push
3. キャンセル

## Phase 4: Project Registration

GitHub Project にアイテムを登録する。既存アイテムには対話的操作を提供する。

**`--skip-project` 指定時はスキップ → Phase 5 へ。**

### 4a. Project 選択

`--project <N>` 指定時はその番号を使用。

未指定時:
1. `gh project list --owner @me --format json` でプロジェクト一覧を取得
2. AskUserQuestion で選択:
   ```
   GitHub Projects:
   1. #{number} {title}
   2. #{number} {title}
   ...
   N. スキップ（Project 登録しない）
   ```
3. 「スキップ」選択時 → Phase 5 へ

### 4b. 既存アイテムチェック

```bash
gh project item-list {project_number} --owner @me --format json --limit 100
```

PR URL で照合。アイテム数が多い場合は `--limit` を段階的に増やす（100 → 300 → 全件）。

### 4c. 未登録 → 新規登録

```bash
gh project item-add {project_number} --owner @me --url {pr_url}
```

### 4d. 登録済み → 対話的操作

AskUserQuestion で操作を選択（ループ形式）:

```
PR #{pr_number} は既にプロジェクト「{project_title}」に登録されています。
Status: {current_status}

どうしますか？
1. ステータスを変更する
2. サブタスク（Draft Issue）を追加する
3. PR にコメントを追加する
4. DONE にする
```

**ステータス変更:**
1. `gh project field-list {N} --owner @me --format json` で Status フィールドの選択肢を取得
2. AskUserQuestion で新しいステータスを選択
3. `gh project item-edit --id {item_id} --field-id {field_id} --project-id {project_id} --single-select-option-id {option_id}`

**サブタスク追加:**
1. AskUserQuestion でタイトルを入力
2. `gh project item-create {N} --owner @me --title "{title}" --body "Parent: #{pr_number}"`

**コメント追加:**
1. AskUserQuestion でコメント内容を入力
2. `gh pr comment {pr_number} --body "{comment}"`

**DONE にする:**
1. Status フィールドの Done オプション ID を取得
2. ステータスを Done に更新

操作完了後、再度 AskUserQuestion で追加操作の有無を確認。「完了」選択で Phase 5 へ。

## Phase 5: Report

```
## GitHub Ops 完了

### PR
- {作成/更新}: #{number} {title}
- URL: {url}
- Status: {open/draft}

### Project
- Project: {project_title} (#{project_number})
- アクション: {登録/ステータス変更/サブタスク追加/スキップ}
```

## Error Handling

| Phase | エラー | 対応 |
|-------|--------|------|
| Prerequisites | `gh` 未インストール | 案内して終了 |
| Prerequisites | 未認証 | 「`gh auth login` を実行してください」と案内 |
| Prerequisites | `project` スコープ未付与 | 「`gh auth refresh -s project` を実行してください」と案内 |
| 1 | Git リポジトリ外 | 報告して終了 |
| 1 | リモート未設定 | 報告して終了 |
| 1 | detached HEAD | AskUserQuestion でブランチ名を確認 |
| 3 | `git push` 失敗 | 3d の対話フローに従う |
| 3 | `gh pr create` 失敗 | エラー表示、リトライ確認（最大2回） |
| 4 | Project 0件 | 報告して Phase 4 をスキップ |
| 4 | `gh project item-add` 失敗 | エラー表示、リトライ確認（最大2回） |
| 4 | Status フィールド未検出 | フィールド一覧を表示して手動選択を提案 |
| 全体 | API レート制限 | 30秒待機リトライ（最大3回） |

## Red Flags

**禁止事項:**
- ユーザー承認なしの PR 作成/更新/Project 操作
- main/master ブランチへの force push（対話でも拒否）
- PR body にシークレット（.env、トークン等）を含めること
- project-state.json の全文を PR body にコピーすること（要約して使う）
- Phase 2 の既存 PR チェックのスキップ
- Phase 4 の既存アイテムチェックのスキップ

**必須事項:**
- Phase 遷移時のアナウンス
- PR 作成/更新前のプレビュー表示とユーザー承認
- Project 操作前の現在状態の表示
- Push 前のリモートとの差分状態の確認
- PR URL を Phase 5 のレポートに含めること
