---
name: audit-gate-protocol
description: >-
  パイプライン系スキル（feature-dev / debug-flow）共通の Audit Gate プロトコル。Phase 完了後の監査フロー、
  Fix Dispatch 戦略、Re-gate + Re-review ループ、PAUSE 復帰の全手順を定義する。
---

# Audit Gate Protocol

<HARD-GATE>
このプロトコルは任意ではない。各フェーズ完了後の Audit Gate 実行は必須である。
done-criteria の `audit: required` フェーズで phase-auditor を起動せずに遷移した場合、
パイプラインの品質保証は無効となる。
</HARD-GATE>

フェーズ番号と基準 ID（`D5-02` 等）は呼び出し元スキルごとに異なる。本ファイルは**フェーズの役割**で規定し、
番号・基準 ID には踏み込まない。自スキルのどのフェーズがどの役割かは、各スキルの Autonomy Summary の
「役割」列を参照する。基準の実体は各スキルの done-criteria に定義される。

## 呼び出し元スキルが定義するもの

| 項目 | 内容 |
|------|------|
| pipeline 識別子 | handover の `pipeline` に記録するスキル名 |
| フェーズ ⇄ 役割の対応 | 各スキルの Autonomy Summary の「役割」列 |
| done-criteria | フェーズごとの基準ファイル（`audit`・`max_retries`・基準 ID を含む） |
| 有効フェーズ | フラグに応じて実行されるフェーズの集合 |

## 1. Audit Gate フロー

Phase N 完了後、以下の 6 ステップで Audit Gate を実行する。

```
### Phase N 完了後: Audit Gate

1. 成果物パスを `artifacts` に記録する
2. 該当フェーズの done-criteria を Read で読み込む
3. Evidence Plan から該当アクティビティタイプの collection 要件が
   Executor に注入済みであることを確認
4. Audit Agent を起動:
   - `--swarm` 無効時: 単一の `phase-auditor` を Agent ツールで起動（Audit Context を注入）
   - `--swarm` 有効時 かつ inspection 基準あり: Audit Team を起動（後述セクション 10 参照）
   - `--swarm` 有効時 かつ inspection 基準なし: 単一の `phase-auditor`
5. 返却値の JSON 有効性と必須フィールドを検証
   - 不正な場合: 1回だけ再起動（fix loop とは別カウント）
   - 2回目も不正: PAUSE
6. verdict を判定:
   - PASS: quality_warnings をユーザーに提示し Phase N+1 へ進む
   - FAIL かつ escalation != null: 即 PAUSE（escalation 内容を提示）
   - FAIL かつ attempt < max_retries:
     a. FAIL 項目の fix_instruction を抽出
     b. Phase N の Fix Dispatch 戦略に従い修正を実行
     c. 累積診断を更新（Audit Agent が算出した diff_from_previous を append）
     d. attempt を +1 して手順 4 に戻る
   - FAIL かつ attempt >= max_retries:
     a. 累積診断レポートを生成
     b. PAUSE: ユーザーに提示し判断を委任
```

## 2. Audit Context テンプレート

Audit Agent（phase-auditor）への注入内容。

```markdown
## Audit Context

### Phase
phase: {N}
name: {phase_name}
attempt: {current_attempt}

### Done Criteria
{該当フェーズの done-criteria の全文}

### Evidence Plan
{evidence-plan.md の全文、または "未生成" }

### Artifacts to Verify
- primary: {成果物パス}
- dependencies: [{前フェーズ成果物}]

### Available Capabilities
- bash: true
- browser-automation: {playwright | chrome-in-chrome | none}
- database-access: {MCP server name | none}
- api-access: {true | false}

### Pipeline Configuration
active_phases: [{フラグに応じて有効なフェーズ番号}]
next_phase: {N+1 or skip先}

### Cumulative Diagnosis (attempt 2+ only)
{前回までの診断履歴 JSON}
```

## 3. Fix Dispatch 戦略

修正はオーケストレーターが **そのフェーズで使った既存のサブエージェント/スキル** に再委任する。

| 役割 | Fix Executor | Fix Dispatch 戦略 |
|------|-------------|-------------------|
| 起点（Design / RCA） | オーケストレーター自身 | 起点成果物を修正。不足情報があれば探索エージェント（code-explorer, impact-analyzer 等）を再起動 |
| 設計レビュー | オーケストレーター自身 | 設計書を修正 |
| 計画 | オーケストレーター自身 | 計画書を修正 |
| 計画レビュー | オーケストレーター自身 | 計画書を修正 |
| Execute | `feature-implementer` | fix_instructions をタスク単位に分解し、`subagent_type: "feature-implementer"` で起動（TDD skills 自動注入） |
| Doc Audit（feature-dev） | オーケストレーター / doc-check / `feature-implementer` | 修正種別で振り分け: depends-on→Edit、内容更新→doc-check、新規作成→feature-implementer |
| Smoke Test | `feature-implementer` | Execute フェーズの `feature-implementer` を再起動 |
| コードレビュー | `feature-implementer` | Execute フェーズの `feature-implementer` を再起動 |
| テストレビュー | `feature-implementer` | Execute フェーズの `feature-implementer` を再起動 |
| Integrate | オーケストレーター自身 | Audit Gate Lite のため Agent 不要 |

## 4. Fix Context テンプレート

サブエージェント再起動時は文脈が失われるため、以下を注入する。

```markdown
## Fix Context

### Original Task
{計画書から該当タスクの定義}

### Changes Made
{該当タスクが生成した git diff}

### Fix Instructions
{Audit Agent からの fix_instruction 全文: what/how/source/why/verify}

## Evidence Collection Requirements
{Evidence Plan から該当アクティビティタイプの collection 要件}

## Return Format
完了後、以下の JSON 形式で結果を返すこと:
{
  "fix_status": "completed | partial | blocked",
  "completed_fixes": ["基準ID", ...],
  "blocked_fixes": [{ "criteria_id": "...", "reason": "...", "suggestion": "..." }],
  "changes_summary": "変更内容のサマリ"
}
```

fix_status の挙動:
- `completed`: 通常通り Audit Agent で再監査
- `partial`: 完了分は再監査、blocked 分は累積診断に記録
- `blocked`: 即 PAUSE（修正不能）

## 5. INTERACTIVE フェーズでの Audit Gate 位置

レビュー系の役割（設計レビュー / 計画レビュー / コードレビュー / テストレビュー）は既にレビューループを持つ。
Audit Gate は **既存レビューループ完了後に 1 回だけ** 実行する。レビュー自体の再実行は行わない。

```
設計レビュー: /spec-review 実行 → findings ループ（既存） → PASS
         → Audit Gate（該当フェーズの done-criteria の全基準を検証）
         → PASS → 次フェーズへ
         → FAIL → 修正 → 再監査（レビュー自体は再実行しない）
```

## 6. PAUSE 復帰プロトコル

Audit Gate が PAUSE に到達した後、ユーザーが介入して再開する場合の手順。

1. ユーザーが修正を行った後「続行」を指示
2. attempt カウンタをリセット（1 に戻す）
3. 累積診断は保持（ユーザー修正前の履歴として有用）
4. cumulative_diagnosis に `"user_intervention": true` のマーカーを付与
5. Audit Agent を新たに起動（attempt=1、累積診断はコンテキストとして注入）

## 7. Handover State 拡張

パイプライン handover 時に保存する `audit_state` の JSON 構造。

```json
{
  "pipeline": "{pipeline 識別子}",
  "current_phase": 5,
  "audit_state": {
    "current_attempt": 2,
    "max_retries": 3,
    "cumulative_diagnosis": [
      {
        "attempt": 1,
        "failed_criteria": ["{基準ID}", "{基準ID}"],
        "details": { "{基準ID}": "..." },
        "diff_from_previous": null
      }
    ],
    "last_fix_dispatch": {
      "strategy": "subagent-relaunch",
      "target_tasks": ["task-3", "task-5"],
      "fix_summary": "..."
    }
  },
  "artifacts": {
    "design_doc": "docs/plans/...",
    "plan_doc": "docs/plans/...",
    "evidence_plan": "docs/plans/...",
    "worktree_path": "...",
    "branch_name": "...",
    "branch_base": "統合先から分岐した commit。未設定なら `git merge-base HEAD <既定ブランチ>` で求める"
  },
  "args": { "各スキルの Options に定義されたフラグ": "復元可能な値" }
}
```

## 8. Execute Re-gate + Re-review ループ

Execute 以降でコード変更が発生した場合、GitHub PR の「push fix -> CI -> re-review」サイクルを再現する。
CI（Execute / Doc Audit / Smoke Test の Re-gate）だけでなく、レビュー自体も再実行する。

### 8.1 GitHub PR フローとの対比

```
GitHub PR:
  push → CI → review → changes requested
    → push fix → CI → re-review → changes requested
    → push fix → CI → re-review → approved → merge

パイプライン:
  Execute → Audit → [Doc Audit] → [Smoke Test] → コードレビュー → findings → fix
    → Execute Re-gate → [Doc Audit Re-gate] → [Smoke Test Re-gate] → /code-review(re-review) → findings → fix
    → Execute Re-gate → [Doc Audit Re-gate] → [Smoke Test Re-gate] → /code-review(re-review) → no findings
    → コードレビュー Audit Gate → Integrate(merge)
```

| GitHub PR | パイプライン |
|-----------|-------------|
| push | コード変更（fix 適用） |
| CI | Execute Re-gate + Doc Audit Re-gate + Smoke Test Re-gate |
| review / re-review | /code-review（または /test-review） |
| approve | コードレビュー / テストレビューの Audit Gate |
| merge | Integrate |

### 8.2 フロー詳細

```
コードレビュー: /code-review → findings → 修正適用
  |
  +-- git diff でコード変更を検知
  |
  +-- コード変更あり → Re-review ループ開始
  |    |
  |    +-- Step 1: Execute の Audit Gate 再実行（full mode）
  |    |    +-- PASS -> Step 2
  |    |    +-- FAIL -> Fix -> Execute Re-gate 再実行 -> (max_retries -> PAUSE)
  |    |
  |    +-- Step 2: Doc Audit Re-gate（--doc 有効時のみ、lightweight）
  |    |    +-- doc-audit.sh --range <fix-commit>..HEAD 実行
  |    |    +-- 影響なし -> Step 3
  |    |    +-- 影響あり -> doc-check のみ実行（Layer 2 再実行なし）-> Step 3
  |    |
  |    +-- Step 3: Smoke Test の Audit Gate 再実行（--smoke 有効時）
  |    |    +-- PASS -> Step 4
  |    |    +-- FAIL -> Fix -> Step 1 に戻る（コード変更が発生するため）
  |    |
  |    +-- Step 4: /code-review 再実行（修正コードのレビュー）
  |    |    +-- findings なし -> Step 5
  |    |    +-- findings あり -> ユーザー承認 -> 修正適用
  |    |         -> Step 1 に戻る（コード変更が発生するため）
  |    |
  |    +-- Step 5: コードレビューの Audit Gate
  |
  +-- コード変更なし
       +-- コードレビューの Audit Gate のみ
```

テストレビューも同様（/code-review の代わりに /test-review）。

### 8.3 ループ終了条件

Re-review ループは以下のいずれかで終了する:

1. **正常終了**: Execute Re-gate PASS -> Doc Audit Re-gate PASS -> Smoke Test Re-gate PASS -> re-review で findings なし -> コードレビューの Audit Gate へ
2. **PAUSE（Re-gate 失敗）**: Execute or Smoke Test の Re-gate が max_retries に到達
3. **PAUSE（Re-gate escalation）**: Execute Re-gate で escalation が発生
4. **PAUSE（re-review 繰り返し）**: re-review が 3 回連続で findings を出す場合、PAUSE して根本的な設計見直しを促す

### 8.4 Re-gate の attempt カウンタ

- Re-gate は呼び出し元（コードレビュー / テストレビュー）の attempt とは独立したカウンタを持つ
- 各 Re-review ループの開始時に Re-gate の attempt はリセットされる
- max_retries は Execute / Smoke Test の done-criteria に定義された値を使用

### 8.5 Evidence 再収集

Re-gate 実行時、Evidence Plan の collection 要件も再適用される:

- Execute Re-gate: implementation アクティビティのエビデンスを再収集
- Doc Audit Re-gate: doc-maintenance アクティビティのエビデンスを再収集（lightweight: doc-audit.sh + doc-check のみ）
- Smoke Test Re-gate: smoke-test アクティビティのエビデンスを再収集
- エビデンスファイルは上書き（最新の状態が常に反映される）

### 8.6 Re-gate + Re-review が解決する問題

| 発生元 | リスク | 検出手段 |
|--------|--------|---------|
| コードレビュー | 修正でビルドが壊れる | Execute Re-gate（ビルド/コンパイル基準） |
| コードレビュー | 修正で既存テストが FAIL | Execute Re-gate（全テスト PASS 基準） |
| コードレビュー | 修正でコンポーネント境界を破壊 | Execute Re-gate（設計整合性の inspection 基準） |
| コードレビュー | 修正でドキュメントが乖離する | Doc Audit Re-gate |
| コードレビュー | 修正で UI が壊れる | Smoke Test Re-gate |
| コードレビュー | 修正が新たなセキュリティ問題を導入 | re-review（security 観点） |
| コードレビュー | 修正が新たなパフォーマンス問題を導入 | re-review（performance 観点） |
| テストレビュー | テスト追加で既存テストとの競合 | Execute Re-gate（全テスト PASS 基準） |
| テストレビュー | テスト修正がトレーサビリティを破壊 | Execute Re-gate（タスク ⇄ コード変更の対応基準） |

## 9. Audit Gate Lite（Integrate）

Integrate フェーズの done-criteria は `audit: lite` である。Audit Agent を起動せず、オーケストレーターが
基準を直接検証する（git コマンド等での確認、および inspection 基準がある場合は自身の判定）。

基準の実体は各スキルの Integrate フェーズの done-criteria に定義される。統合方法の選択・実行完了・
コンフリクト有無といった機械的に確認できる項目が中心のため、Agent の judgment を必要としない。

## 10. Audit Team（`--swarm` 有効時）

`--swarm` フラグ有効時、inspection 基準を含むフェーズの Audit Gate をエージェントチームで実行する。
automated 基準のみのフェーズは単一エージェントのまま。`audit: lite` の Integrate フェーズは対象外。

### 10.1 チーム構成

```
Team: audit-{feature}-phase-{N}
Leader: オーケストレーター

Member A（automated-verifier）:
  - automated 基準の全評価
  - Layer 1 evidence（claimed）の存在確認
  - ビルド/lint/テスト等の実行結果の検証

Member B（inspection-verifier）:
  - inspection 基準の全評価
  - トレーサビリティ、網羅性、整合性の判定
  - pass_condition に対する判断

Member C（evidence-verifier）:
  - Layer 2 evidence（verified）の独立再検証
  - available capabilities に応じてテスト再実行、DB 直接確認、URL アクセス等
  - claimed evidence と verified 結果の照合
```

### 10.2 チーム動作フロー

```
1. TeamCreate で Audit Team を作成
2. 3メンバーに Audit Context + Done Criteria + Evidence Plan を配布
3. 各メンバーが担当範囲の基準を独立評価
4. メンバー間で findings を共有・相互検証:
   - A が automated で PASS した項目を B が inspection 観点で再確認
   - C の Layer 2 検証結果が A の Layer 1 結果と矛盾する場合に議論
   - B の inspection 判定に C が evidence で裏付けまたは反証
5. チームが合意した verdict + criteria_results を統合出力
6. チーム完了後クリーンアップ
```

### 10.3 verdict の合意ルール

- automated 基準: Member A の結果が最終（機械的検証に議論は不要）
- inspection 基準: Member B の判定に Member A/C が異議を唱えた場合、議論で解決
- evidence 検証: Layer 2 結果が Layer 1 と矛盾する場合、Layer 2 を優先（独立検証の方が信頼性が高い）
- 最終 verdict: 全 blocker 基準が PASS で合意 → PASS、いずれかで FAIL 合意 → FAIL

### 10.4 出力プロトコル

チームの統合出力は単一 phase-auditor と同一の JSON 形式。オーケストレーターから見た Audit Gate フロー（ステップ 5 以降）は変わらない。

```json
{
  "phase": N,
  "attempt": N,
  "verdict": "PASS | FAIL",
  "criteria_results": [...],
  "summary": {
    "total": N, "passed": N, "failed": N,
    "blocking_issues": [...],
    "quality_warnings": [...],
    "verification_coverage": {
      "fully_verified": N,
      "claimed_only": N,
      "unverifiable": N
    }
  },
  "escalation": null | {...},
  "diff_from_previous": null | {...}
}
```

### 10.5 適用条件

適用の判定は done-criteria の実体で行う。フェーズ番号で固定しない。

| 条件 | Audit Team 適用 |
|------|----------------|
| done-criteria に inspection 基準が 1 件以上ある | Yes。inspection 基準が多いフェーズ（Execute 等）が最も恩恵を受ける |
| done-criteria が automated 基準のみ | No — 単一 phase-auditor |
| done-criteria が `audit: lite`（Integrate） | No — オーケストレーターが直接検証（セクション 9） |

メンバーへの基準割り当ては verify_type で決まる（セクション 10.1）。automated → Member A、
inspection → Member B、Layer 2 evidence の再検証 → Member C。

### 10.6 単一エージェントとの使い分け

| | 単一 phase-auditor（デフォルト） | Audit Team（--swarm） |
|---|---|---|
| inspection 判定 | 1エージェントの判断 | 3エージェントの相互検証 |
| evidence 検証 | 1エージェントが L1+L2 両方 | 専任メンバーが L2 に集中 |
| コスト | 低 | 高（3インスタンス） |
| 偽陽性/偽陰性 | 単一判断のブレリスク | 相互検証で低減 |
| 推奨場面 | 通常開発 | 高品質要求・クリティカルな機能開発 |
