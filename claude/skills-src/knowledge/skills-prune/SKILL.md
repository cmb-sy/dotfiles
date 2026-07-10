---
name: skills-prune
description: >-
  スキルの棚卸し・メンテナンスをしたいときに使う。利用ログを集計して未使用・低使用スキルを
  特定し、未使用理由を分析して改善案（description/引数/導線）または削除提案を出す。
  対象期間・件数・特定スキルの深掘りは argument-hint を参照。
argument-hint: "[--window <days>] [--top <n>] [--focus <skill-name>] [--apply-draft]"
user-invocable: true
---

# Skills Prune

`claude/skills` の利用実績を監査し、使われていないスキルを「改善すべきか / 削除すべきか」まで判断する棚卸しスキル。

**開始時アナウンス:** 「Skills Prune を開始します。Phase 1: Inventory」

## 目的

- 未使用スキルを感覚ではなくデータで特定する
- 使われない理由を構造的に分析する
- 各スキルに対して `Keep / Improve / Merge / Delete` の推奨を出す

## 引数

- `--window <days>`: 利用実績の分析期間（日数）。デフォルト `30`
- `--top <n>`: 詳細分析する低使用スキル上位件数。デフォルト `10`
- `--focus <skill-name>`: 指定スキルを優先して深掘りする
- `--apply-draft`: 改善案として `SKILL.md` の修正ドラフトまで作成する（実適用前に確認する）

## フェーズ

### Phase 1: Inventory（スキル台帳の作成）

1. `claude/skills/**/SKILL.md` を再帰走査し、以下を抽出:
   - `name`
   - `description`
   - `argument-hint`
   - 依存（他スキル名への invoke 記述）
2. スキル一覧テーブルを作る（欠損メタも記録する）
3. パスからカテゴリを抽出して `category` 列を持たせる（例: `claude/skills/review/code-review/SKILL.md` -> `review`）

## Phase 2: Usage Collection（利用実績の収集）

期間内の transcript / chat log から以下を収集する。

- 直接利用: `/skill-name` 形式
- 間接利用: 他スキル内から invoke された痕跡
- 代替利用: 似た目的で別スキルが使われた痕跡

可能なら以下を優先して探索:
- 現在のエージェント transcript 群
- `~/.claude/projects` 配下の session transcript

各スキルごとに次を算出:

- `direct_count`
- `indirect_count`
- `last_used_at`
- `window_days`

## Phase 3: Unused Classification（未使用判定）

以下のルールで分類する:

- `never-used`: direct=0 かつ indirect=0（観測期間内）
- `dormant`: 利用履歴ありだが `window` 内は 0
- `hidden-dependency`: direct=0 だが indirect>0
- `active`: direct>0

`never-used` と `dormant` を「要分析対象」とする。

## Phase 4: Root Cause Analysis（使われない理由の分析）

各対象スキルに対し、最低 1 つ以上の根本原因を判定する。

原因カテゴリ:

1. **Discoverability不足**  
   description が曖昧、トリガー語が弱い、名前から用途が連想しにくい
2. **導線不足**  
   上位オーケストレータから呼ばれない、README/運用導線に登場しない
3. **重複**  
   他スキルと責務が重なり、より有名なスキルに吸収されている
4. **実行コスト**  
   引数や前提が多く、起動コストが高い
5. **陳腐化**  
   現在のワークフローでは役割が消滅した
6. **信頼性懸念**  
   過去ログで失敗・不安定・結果品質低い記録がある

判定時は evidence を必ず付ける:

- transcript 断片
- 比較対象スキル名
- 呼び出し経路（ある/なし）

## Phase 5: Recommendation（改善 or 削除提案）

各スキルに 1 つの推奨アクションを割り当てる:

- `KEEP`: 現状維持（利用あり・価値明確）
- `IMPROVE`: 名前/description/引数/導線を改善
- `MERGE`: 既存スキルへ統合
- `DELETE`: 削除候補

### 判定ルール

- `DELETE` は次を全て満たす場合のみ:
  - `never-used` または長期 `dormant`
  - 間接依存なし
  - ユニークな価値が説明できない
  - 代替スキルが存在
- `IMPROVE` は次のいずれか:
  - 価値はあるが discoverability/導線が弱い
  - 入力設計を変えれば利用が増える見込みが高い
- `MERGE` は責務重複が高い場合

## 出力フォーマット

以下の順で出力する。

### 1) Overview

```text
Skills Prune Report
window: <days>
total_skills: <N>
active: <N>
hidden_dependency: <N>
dormant: <N>
never_used: <N>
```

### 2) 未使用・低使用スキル一覧

1 スキルにつき最大 8 行:

```text
[skill-name]  class: never-used
- usage: direct=0 indirect=0 last_used=none
- reason: Discoverability不足（description が汎用的）
- evidence: "..."
- recommendation: IMPROVE
- action:
  1) description に trigger 語を追加
  2) feature-dev の Integration 節に導線追加
```

### 3) 削除候補

```text
Delete Candidates
- <skill-name>: 理由 / 代替 / 影響
```

### 4) 改善ドラフト（`--apply-draft` 時のみ）

`IMPROVE` 判定スキルに対して、最小差分ドラフトを提示する。

- name 変更案（必要時）
- description 改善案（WHAT + WHEN + trigger 語）
- argument-hint の簡略化案
- 上位スキルからの invoke 追加候補

## 実行ルール

1. 推測で「未使用」と断定しない。必ずログ根拠を示す
2. direct/indirect を分けて報告する
3. `DELETE` は保守的に判定し、影響を明記する
4. 提案は「今すぐ編集可能な粒度」で出す
5. 出力は簡潔なプレーンテキスト中心で作る

## Red Flags

- 利用実績ゼロの根拠なしで削除提案する
- `hidden-dependency` を未使用扱いして削除提案する
- 改善案が抽象的で実編集に落ちない
- 重複先スキル名を示さず `MERGE` 提案する
