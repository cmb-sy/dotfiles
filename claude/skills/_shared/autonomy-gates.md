---
name: autonomy-gates
description: >-
  パイプライン系スキル（feature-dev / debug-flow）共通の自律動作レベルと GATE 判定ルール。
  フェーズの役割ごとに AUTO / PAUSE / STOP の判定表を定義する。
---

# Autonomy Gates

各フェーズの自律動作レベルと GATE 判定ルール。

フェーズ番号は呼び出し元スキルごとに異なるため、本ファイルは**フェーズの役割**で規定する。
自スキルのどのフェーズがどの役割に当たるかは、各スキルの Autonomy Summary の「役割」列を参照する。
一方のスキルにしか存在しない行は Situation 欄に対象スキルを明記する。

## Gate Decision Table

### 起点フェーズ

| Situation | Action | Rationale |
|-----------|--------|-----------|
| brainstorming が設計質問を提示（feature-dev） | PAUSE | ユーザーの意思決定が必要。自動回答禁止 |
| ユーザーが回答を提供（feature-dev） | AUTO | 次の質問 or 設計書ドラフトへ進む |
| 起点成果物（設計書 / RCA Report）のドラフト完成 | AUTO | worktree 作成を実行 |
| worktree テスト通過 | AUTO | 起点成果物を worktree 内にコミット |
| worktree テスト失敗 | PAUSE | 続行 or STOP をユーザーに提案 |
| 起点成果物が worktree 内にコミット済み | AUTO | 次フェーズへ自動遷移 |
| ユーザーが中断を指示 | STOP | クリーンアップ不要で終了 |

### 設計レビューフェーズ（feature-dev）

| Situation | Action | Rationale |
|-----------|--------|-----------|
| レビューエージェント起動 | AUTO | 並列レビューを自動実行 |
| エージェントエラー | AUTO | 該当エージェントをスキップし残りで続行 |
| レポート生成完了 | PAUSE | ユーザーに findings を提示し修正選択を待つ |
| ユーザーが修正を選択 | AUTO | 選択された findings を修正 |
| 全観点パス | AUTO | handover 実行後に次フェーズへ自動遷移 |
| 3回レビュー不合格 | PAUSE | 設計の根本的見直しを提案 |

### 計画フェーズ

| Situation | Action | Rationale |
|-----------|--------|-----------|
| writing-plans 起動 | AUTO | 計画書作成を自動実行 |
| 計画書がコミット済み | AUTO | 次フェーズへ自動遷移 |
| writing-plans 失敗 | PAUSE | 失敗内容を報告しユーザー判断を仰ぐ |

### 計画レビューフェーズ

| Situation | Action | Rationale |
|-----------|--------|-----------|
| レビューエージェント起動 | AUTO | 並列レビューを自動実行 |
| エージェントエラー | AUTO | 該当エージェントをスキップし残りで続行 |
| レポート生成完了 | PAUSE | ユーザーに findings を提示し修正選択を待つ |
| ユーザーが修正を選択 | AUTO | 選択された findings を修正 |
| 全観点パス | AUTO | handover 実行後に Execute フェーズへ自動遷移 |
| 3回レビュー不合格 | PAUSE | 計画の根本的見直しを提案 |

### Execute フェーズ

| Situation | Action | Rationale |
|-----------|--------|-----------|
| サブエージェントによるタスク実行 | AUTO | 計画書に基づき自動実行 |
| 個別タスク完了 | AUTO | 次のタスクへ進む |
| 全タスク完了 | AUTO | 次フェーズへ自動遷移 |
| タスク失敗（1-2回目） | AUTO | リトライ |
| タスク失敗（3回目） | PAUSE | 設計ギャップをエスカレーション |

### Doc Audit フェーズ（feature-dev）

| Situation | Action | Rationale |
|-----------|--------|-----------|
| Layer 1 の検出スクリプト実行 | AUTO | 読み取りのみ |
| finding の修正方針の選択 | PAUSE | 削除・統合はユーザー判断を要する |
| depends-on の修正 | AUTO | 機械的な整合修正 |
| 全 finding 処理済み | AUTO | 次フェーズへ自動遷移 |
| スクリプト実行失敗 | PAUSE | 検出結果なしで先に進めない |

### Smoke Test フェーズ

| Situation | Action | Rationale |
|-----------|--------|-----------|
| `--smoke` 未指定かつ UI 関連なし | AUTO | Smoke Test をスキップして次フェーズへ |
| UI 関連キーワード検出 | PAUSE | 自動有効化をユーザーに提案 |
| smoke-test 起動 | AUTO | 4ステップを自動実行 |
| サーバー起動不可 | PAUSE | ユーザーに起動コマンドを確認 |
| VRT 差分検出 | PAUSE | ベースライン更新をユーザーに確認 |
| 全ステップ PASS | AUTO | 次フェーズへ自動遷移 |
| FAIL（修正可能） | AUTO | 自動修正 → 再実行（最大2回） |
| FAIL（修正不能） | PAUSE | ユーザーに報告して判断を委ねる |
| フレーキーテスト検出 | AUTO | 報告のみでブロックしない。次フェーズへ |

### コードレビューフェーズ

| Situation | Action | Rationale |
|-----------|--------|-----------|
| レビューエージェント起動 | AUTO | 並列レビューを自動実行 |
| レポート生成完了 | PAUSE | ユーザーに findings を提示し修正選択を待つ |
| ユーザーが修正を選択 | AUTO | 選択された findings を修正 |
| 修正後テスト通過 | AUTO | handover 実行後に次フェーズへ自動遷移 |
| 修正後テスト失敗（1-2回目） | AUTO | リトライ |
| 修正後テスト失敗（3回目） | PAUSE | 手動対応が必要 |

### テストレビューフェーズ

| Situation | Action | Rationale |
|-----------|--------|-----------|
| `--e2e` 未指定 | AUTO | テストレビューをスキップして次フェーズへ |
| レビューエージェント起動 | AUTO | 並列レビューを自動実行 |
| レポート生成完了 | PAUSE | ユーザーに findings を提示し修正選択を待つ |
| ユーザーが修正を選択 | AUTO | 選択された findings を修正 |
| 修正完了・テスト通過 | AUTO | handover 実行後に次フェーズへ自動遷移 |
| テスト追加後の既存テスト破損 | PAUSE | 影響範囲を報告 |

### Integrate フェーズ

| Situation | Action | Rationale |
|-----------|--------|-----------|
| 統合方法の選択肢提示 | PAUSE | wt merge / PR / ブランチ保持 / 破棄はユーザーが選択する |
| ユーザーが wt merge を選択 | AUTO | worktrunk スキルを invoke し `wt merge` を実行 |
| ユーザーが PR を選択 | AUTO | `git push -u` + `gh pr create` → `wt remove` |
| ユーザーがブランチ保持を選択 | AUTO | 何もしない |
| ユーザーが破棄を選択 | AUTO | `wt remove` を実行 |
| マージコンフリクト | PAUSE | コンフリクトを報告し手動解決を提案 |
| 統合完了 | AUTO | パイプライン完了 |

### 全フェーズ共通

| Situation | Action | Rationale |
|-----------|--------|-----------|
| Context 逼迫 | PAUSE | `/handover` を実行してパイプライン状態を保存 |
| `--codex` 指定時に Codex 接続失敗 | AUTO | 警告し codex なしで続行 |

### Audit Gate

| Situation | Action | Rationale |
|-----------|--------|-----------|
| Audit Gate: verdict PASS | AUTO | 全 blocker 基準 PASS。quality_warnings をユーザーに提示し次フェーズへ |
| Audit Gate: verdict FAIL, attempt < max_retries | AUTO | Fix Dispatch → 再監査のループを自動実行 |
| Audit Gate: verdict FAIL, attempt >= max_retries | PAUSE | 累積診断レポートを提示しユーザー判断を委任 |
| Audit Gate: escalation != null | PAUSE | 前フェーズの成果物に根本原因。残 attempt に関わらず即 PAUSE |
| Audit Gate: fix_status blocked | PAUSE | 修正不能。即 PAUSE |
| Audit Gate: Agent output invalid (2回目) | PAUSE | Audit Agent の出力が不正。手動確認を依頼 |
| Re-gate: Execute PASS + Smoke Test PASS | AUTO | Re-review を実行 |
| Re-gate: re-review で findings なし | AUTO | コード/テストレビューフェーズの Audit Gate へ |
| Re-gate: re-review が3回連続 findings | PAUSE | 根本的な設計見直しを促す |

## Autonomy Mode 定義

| Mode | 説明 |
|------|------|
| INTERACTIVE | ユーザーとの対話が必要。判断ポイントで必ず PAUSE |
| AUTONOMOUS | 自動実行。失敗時のみ PAUSE |
| AUTONOMOUS+GATE | 自動実行だが、特定条件（テスト失敗、累積エラー）で PAUSE |

## 原則

- PAUSE はユーザーの意思決定を待つことを意味する
- AUTO は次のステップへ自動的に進むことを意味する
- STOP はパイプラインを終了することを意味する
- 判断に迷った場合は PAUSE を選択する
