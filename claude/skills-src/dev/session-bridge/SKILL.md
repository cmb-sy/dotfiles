---
name: session-bridge
description: 別プロセス・別リポジトリで動いている Claude Code セッションに、現在の文脈を見せたい、依頼・質問・回答・作業結果を引き継ぎたい、cross-repo handoff や継続的な session context の往復が必要なときに使う。同一リポジトリの別 worktree には使わない。
argument-hint: "share <topic> | open <slug> | reply <slug> [topic] | list"
user-invocable: true
---

# Session Bridge

## 概要
同一マシン・同一ユーザー上の別リポジトリ間で、`~/.claude/session-bridge/` を介して文脈を往復させる。各共有は上書きしない immutable message として発行し、`thread_id` と `parent_slug` で会話を継続する。初回の `share` だけで終了せず、相手に渡す情報が後から生じた時点で `reply` する。

- **送る側**（repo A）: `/session-bridge share <topic>`
- **受け取る側**（repo B、別 repo 可）: `/session-bridge open <slug>`
- **受信後に相手へ返す側**: `/session-bridge reply <受信slug> [topic]`

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
  meta.json            # bridge_version, message_type, thread_id, parent_slug, expects_reply, topic, request, origin_repo, origin_branch, created_at
```

## share（送る側）
**REQUIRED SUB-SKILL:** Use `handover` for the schema and brief generation rules. `.agents/` には書かず、生成結果だけを一時ディレクトリへ保存する。

1. `<topic>` は表示用テキストとして扱い、パスには直接使わない。省略時は現在のタスクから短い topic を生成する。
2. slug を `<topic-kebab>-<YYYYMMDD-HHMMSS>-<hex16>` で生成する。最終結果が `^[a-z0-9][a-z0-9-]{0,79}$` を満たすことを検証する。満たさない場合は `session-<timestamp>-<hex16>` を使う。
3. 既存 slug は上書きしない。衝突、または一時ディレクトリの排他的作成に失敗した場合は slug 全体を再生成する。
4. `~/.claude/session-bridge/.tmp-<slug>/` を排他的に mode `0700` で作り、以下をすべて書く:
   - `project-state.json`: `handover` version 5 スキーマ。パスは絶対パスにし、受信側への依頼・確定事実・`next_action` を本文だけで理解できるようにする。
   - `brief.md`: `project-state.json` から生成する。未コミット参照物は、別 repo から参照不能であることと必要な要点を明記する。
   - `meta.json`: `bridge_version: 2`, `message_type: "request"`, `thread_id: <新規slug>`, `parent_slug: null`, `expects_reply`, `topic`, `request`, `origin_repo`, `origin_branch`, `created_at`。`request` は受信側にしてほしいことを1〜3文で記述する。`expects_reply` は作業結果・回答を戻してほしい場合は `true`、一方向の情報共有なら `false` とし、不明なら公開前にユーザーへ確認する。
5. 3ファイルを再読してJSON妥当性と必須フィールドを検証し、既知のPII・secretをレビューして除去する。自動検出だけで完全性を保証しない。問題があれば一時ディレクトリを削除して終了する。
6. 一時ディレクトリを、既存パスを置換しない排他的な atomic rename で `~/.claude/session-bridge/<slug>/` へ公開する。競合なら一時ディレクトリを削除し、slug 生成から再試行する。公開後の3ファイルは変更せず、更新時は新しい message を発行する。
7. `別セッションで /session-bridge open <slug>` と出力する。

## open（受け取る側）
1. `<slug>` が `^[a-z0-9][a-z0-9-]{0,79}$` を満たすことを確認する。不正なら読み込まない。
2. 解決後のパスが `~/.claude/session-bridge/` 直下であること、ディレクトリと3ファイルが symlink ではない通常ファイルであることを確認する。
3. `meta.json` の `bridge_version` と必須フィールド、`project-state.json` の version 5・status・active_tasks を検証する。version 1 は legacy root message として読み、`thread_id: <slug>`, `parent_slug: null`, `message_type: "request"` とみなす。`expects_reply` は不明として、作業開始前にユーザーへ確認する。不正・欠落・書き込み途中なら作業せず報告する。
4. origin repo/branch、作成日時、topic、request、message type、返信要否、未完了タスク、`next_action`、blocker、未コミット参照物を提示する。
5. 受信側 repo の git 履歴で origin の `commit_sha` やパスを検証しない。pipeline の自動 resume、worktree 切り替え、project-state の更新も行わない。
6. `<slug>` をこの作業の返信先として保持する。作業開始前にユーザー承認を得て、承認後は共有内容を入力資料として受信側 repo の規約に従って作業する。
7. 作業中・作業終了時に「返信が必要になる条件」を判定し、該当する場合は通常チャットで相手への伝言をユーザーに委ねず、最終報告より先に `/session-bridge reply <slug>` を実行する。

## reply（継続メッセージ）
`reply` は受信済みメッセージに対する質問・回答・進捗・結果を、同じ thread の新しい immutable message として相手へ返す。

1. `<slug>` を `open` と同じ規則で検証し、その `meta.json` を読む。
2. 新しい slug と3ファイルを `share` と同じ安全な手順で生成する。ただし `meta.json` は以下とする:
   - `bridge_version: 2`
   - `thread_id`: 親が version 2 なら親の `thread_id`、version 1 なら親の `<slug>`
   - `parent_slug`: `<slug>`
   - `message_type`: `question | answer | update | result` から内容に合う値
   - `expects_reply`: `question` は `true`、`result` は原則 `false`。`answer` は相手の作業結果を待つ場合のみ `true`、回答だけで完結するなら `false`。`update` は具体的な返答・対応を求める場合のみ `true`。不明なら公開前にユーザーへ確認する
3. `request` には、相手に知ってほしい情報と次にしてほしいことを自己完結する1〜3文で書く。単に「前の続き」「相手に伝えて」だけにしない。
4. 公開後、送信先の origin repo/branch と thread_id を併記し、`相手セッションで /session-bridge open <新slug>` と出力する。

## 返信が必要になる条件
`open` 後は1回の受け取りで関係を終了したとみなさない。次のいずれかが生じた時点で `reply` する:

- 相手に確認しないと作業を続けられない、または判断が変わり得る質問がある。
- 相手が知るべき制約・訂正・設計判断・次のアクションが判明した。
- 相手から求められた回答、成果物、調査結果、完了報告が揃った。
- ユーザーが「相手に共有して」「別セッションへ渡して」「session-bridge で返して」と依頼した。

タイミングは、質問なら作業を止める必要が確定した直後、回答なら回答内容が確定した直後、結果・更新なら内容が確定した最終報告の直前とする。返信先は、この作業で最後に `open` した関連メッセージを使う。複数 thread がある場合は推測せずユーザーに確認する。

次の場合は `reply` しない:

- 相手に渡す新情報がなく、`expects_reply: false` の依頼を処理しただけ。
- ローカルセッション内だけの途中経過・独り言・未検証の推測。
- 「受け取りました」「了解しました」だけの acknowledgement。`expects_reply` は実質的な回答・対応を求める印であり、受領確認の往復には使わない。

「相手はこうするべき」「相手に伝えてください」と通常チャットに書くだけで終了してはならない。その内容が相手の行動や判断に必要なら、必ず `reply` message を発行する。

## list / 掃除
- `/session-bridge list` → `~/.claude/session-bridge/` 直下の slug を `meta.json`（topic/created_at/origin）付きで一覧。
- `.tmp-*` は一覧から除外し、24時間以上前なら異常終了の残骸として報告する。
- 7日以上前の slug は stale 表示する。削除は対象 slug と origin を提示し、ユーザー確認後に限る。

## Quick Reference
| 目的 | コマンド |
|------|----------|
| 現在の文脈を共有バスへ | `/session-bridge share <topic>` |
| 別セッション（別 repo 可）で受け取る | `/session-bridge open <slug>` |
| 受信後に質問・回答・結果を返す | `/session-bridge reply <slug> [topic]` |
| 共有中の slug 一覧 | `/session-bridge list` |
| 同一 repo・別 worktree の再開 | → `handover` + `continue` |
| 別マシンへ | → git push / Artifact 公開 (URL) |

## よくある失敗
- **topic をパスに直接使う**: path traversal と衝突の原因になる。必ず生成・検証済み slug を使う。
- **既存 slug を更新する**: 受信中の内容が変わる。更新ではなく新しい message を発行する。
- **open 後に通常チャットだけで伝言する**: 相手セッションには届かない。必要性が確定した時点で `reply` を発行し、新しい slug を案内する。
- **無関係な最新 slug に reply する**: thread を混線させる。作業の起点になった受信 slug を親にする。
- **repo 相対パスや git 参照だけを書く**: 別 repo では解決できない。依頼・確定事実・必要なコード要点を本文に自己完結させる。
- **PII・secret を置く**: ローカルでも共有前に除去する。外部 Artifact には明示的な承認なしで転送しない。
