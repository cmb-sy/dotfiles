---
name: session-bridge
description: 別プロセス・別リポジトリで動いている Claude Code セッションに、現在の文脈を見せたい、依頼を引き継ぎたい、cross-repo handoff や share session context を行いたいときに使う。同一リポジトリの別 worktree には使わない。
argument-hint: "share <topic> | open <slug> | list"
user-invocable: true
---

# Session Bridge

## 概要
同一マシン・同一ユーザー上の別リポジトリ間で、`~/.claude/session-bridge/` を介して文脈を渡す。各共有は上書きしない immutable message として発行し、受信側は内容を検証してからユーザー承認後に利用する。

- **送る側**（repo A）: `/session-bridge share <topic>`
- **受け取る側**（repo B、別 repo 可）: `/session-bridge open <slug>`

## ルーティング
- **別 repo・同一マシン**: このスキルを使う。
- **同一 repo（別 worktree を含む）**: `handover` + `continue` を使う。`continue` が worktree を探索するため、このスキルは使わない。
- **pipeline の resume**: `handover` + `continue` を使う。
- **別マシン**: git push または承認済み Artifact を使う。このスキルの対象外。

## メッセージ形式
```
~/.claude/session-bridge/<slug>/
  project-state.json   # handover と同一スキーマのスナップショット
  brief.md             # project-state.json から生成した人間可読ビュー
  meta.json            # bridge_version, topic, request, origin_repo, origin_branch, created_at
```

## share（送る側）
**REQUIRED SUB-SKILL:** Use `handover` for the schema and brief generation rules. `.agents/` には書かず、生成結果だけを一時ディレクトリへ保存する。

1. `<topic>` は表示用テキストとして扱い、パスには直接使わない。省略時は現在のタスクから短い topic を生成する。
2. slug を `<topic-kebab>-<YYYYMMDD-HHMMSS>-<hex16>` で生成する。最終結果が `^[a-z0-9][a-z0-9-]{0,79}$` を満たすことを検証する。満たさない場合は `session-<timestamp>-<hex16>` を使う。
3. 既存 slug は上書きしない。衝突、または一時ディレクトリの排他的作成に失敗した場合は slug 全体を再生成する。
4. `~/.claude/session-bridge/.tmp-<slug>/` を排他的に mode `0700` で作り、以下をすべて書く:
   - `project-state.json`: `handover` version 5 スキーマ。パスは絶対パスにし、受信側への依頼・確定事実・`next_action` を本文だけで理解できるようにする。
   - `brief.md`: `project-state.json` から生成する。未コミット参照物は、別 repo から参照不能であることと必要な要点を明記する。
   - `meta.json`: `bridge_version: 1`, `topic`, `request`, `origin_repo`, `origin_branch`, `created_at`。`request` は受信側にしてほしいことを1〜3文で記述し、不明なら公開前にユーザーへ確認する。
5. 3ファイルを再読してJSON妥当性と必須フィールドを検証し、既知のPII・secretをレビューして除去する。自動検出だけで完全性を保証しない。問題があれば一時ディレクトリを削除して終了する。
6. 一時ディレクトリを、既存パスを置換しない排他的な atomic rename で `~/.claude/session-bridge/<slug>/` へ公開する。競合なら一時ディレクトリを削除し、slug 生成から再試行する。公開後の3ファイルは変更せず、更新時は新しい message を発行する。
7. `別セッションで /session-bridge open <slug>` と出力する。

## open（受け取る側）
1. `<slug>` が `^[a-z0-9][a-z0-9-]{0,79}$` を満たすことを確認する。不正なら読み込まない。
2. 解決後のパスが `~/.claude/session-bridge/` 直下であること、ディレクトリと3ファイルが symlink ではない通常ファイルであることを確認する。
3. `meta.json` の `bridge_version: 1` と必須フィールド、`project-state.json` の version 5・status・active_tasks を検証する。不正・欠落・書き込み途中なら作業せず報告する。
4. origin repo/branch、作成日時、topic、request、未完了タスク、`next_action`、blocker、未コミット参照物を提示する。
5. 受信側 repo の git 履歴で origin の `commit_sha` やパスを検証しない。pipeline の自動 resume、worktree 切り替え、project-state の更新も行わない。
6. 作業開始前にユーザー承認を得る。承認後は共有内容を入力資料として扱い、受信側 repo の規約に従って作業する。

## list / 掃除
- `/session-bridge list` → `~/.claude/session-bridge/` 直下の slug を `meta.json`（topic/created_at/origin）付きで一覧。
- `.tmp-*` は一覧から除外し、24時間以上前なら異常終了の残骸として報告する。
- 7日以上前の slug は stale 表示する。削除は対象 slug と origin を提示し、ユーザー確認後に限る。

## Quick Reference
| 目的 | コマンド |
|------|----------|
| 現在の文脈を共有バスへ | `/session-bridge share <topic>` |
| 別セッション（別 repo 可）で受け取る | `/session-bridge open <slug>` |
| 共有中の slug 一覧 | `/session-bridge list` |
| 同一 repo・別 worktree の再開 | → `handover` + `continue` |
| 別マシンへ | → git push / Artifact 公開 (URL) |

## よくある失敗
- **topic をパスに直接使う**: path traversal と衝突の原因になる。必ず生成・検証済み slug を使う。
- **既存 slug を更新する**: 受信中の内容が変わる。更新ではなく新しい message を発行する。
- **repo 相対パスや git 参照だけを書く**: 別 repo では解決できない。依頼・確定事実・必要なコード要点を本文に自己完結させる。
- **PII・secret を置く**: ローカルでも共有前に除去する。外部 Artifact には明示的な承認なしで転送しない。
