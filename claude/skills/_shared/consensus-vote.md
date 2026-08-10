---
name: consensus-vote
description: >-
  review 系スキルの Phase 2.5（N-way 投票）の共通仕様。同一観点を複数回独立に実行し、
  過半数一致した findings のみを採用する投票アルゴリズム・類似判定・エラーハンドリングを定義する。
---

# Consensus Vote

`iterations > 1` の場合のみ実行する。`iterations == 1` の場合、本 Phase をスキップし Phase 3 へ進む。

**開始時アナウンス:** 「Phase 2.5: Consensus Vote (iterations=N)」

## 呼び出し元スキルが定義するもの

| 項目 | 内容 |
|------|------|
| 観点集合 | 投票対象となるレビュー観点の一覧。各観点は独立に投票する |
| 投票対象外 | 1 回しか実行しない要素（Codex レビュー等）。投票を経ず Phase 3 へ渡す |
| 位置キー | 同一箇所判定に使うフィールド（下記「Semantic Similarity 判定」参照） |

## 投票アルゴリズム

観点ごとに以下を実行する:

1. **基準イテレーション選択**: findings 数が最多のイテレーションを基準（base）とする
2. **投票**: base の各 finding について、他イテレーションに意味的に同一の finding があるかチェックする。`vote_count` が `ceil(iterations / 2)` 以上なら `consensus = true`
3. **補完**: base にないが他イテレーション間で過半数一致する finding を追加採用する

## Semantic Similarity 判定

2つの findings が「同じ問題を指摘している」かの判定基準:

1. **同一箇所**: 呼び出し元スキルが宣言した位置キーが一致する
   - `section` キー（設計書・計画書レビュー）: findings の `section` フィールドが一致または近接する
   - `file` + `line` キー（コード・テストレビュー）: findings の `file` フィールドが一致し、`line` が近い（差 ±10 行以内）、または同一関数内
2. **意味的類似**: description の核心（何が問題か）が一致する。完全一致は不要
3. **severity は不問**: 同じ問題でも severity が異なることがある。consensus に入った場合は最も高い severity を採用する

判定はメインエージェント（スキル実行者）自身が行う。findings は構造化 JSON で返されるため、位置キーの一致・近接で候補を絞り、description を比較する。

## エラーハンドリング

| 状態 | 処理 |
|------|------|
| 成功イテレーション >= 2 | 成功分のみで投票（過半数基準は成功数ベース） |
| 成功イテレーション == 1 | 投票不可。フォールバック: 単一結果をそのまま使用。ユーザーに警告表示 |
| 成功イテレーション == 0 | 全失敗。既存のエラーハンドリングに移行 |
| findings 0 件のイテレーション | 「問題なし」と投票したとみなす。他の finding の vote_count は下がる |
| consensus_findings が 0 件 | レビュー「合格」として Phase 3 へ進む |

## 出力

consensus_findings を Phase 3 に渡す。各 finding に `vote_count` フィールドを付与する。
投票対象外の findings は投票を経ずそのまま Phase 3 に渡す。
