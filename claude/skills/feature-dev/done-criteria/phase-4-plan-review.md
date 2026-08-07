---
phase: 4
name: plan-review
max_retries: 3
audit: required
---

## Criteria

### D4-01: レビューが全3観点で実行され findings が回収されている
- **severity**: blocker
- **verify_type**: automated
- **verification**:
  1. レビュー結果ファイル（`artifacts/reviews/phase-4-review.json` またはレビューログ）を読み取る
  2. clarity, feasibility, consistency の3観点の実行記録が存在するか確認する
  3. 各観点の findings リストが返却されているか確認する（未返却・実行途中終了の観点を検出する）
- **pass_condition**: 記録された観点数が3、かつ findings 未返却の観点が0件
- **fail_diagnosis_hint**: 欠落している観点を特定し、/implementation-review の起動引数を確認する。`--ui` 指定時の追加観点は3観点の数に含めない。consistency 観点には設計書パスが追加コンテキストとして渡されている必要がある
- **depends_on_artifacts**: [artifacts/reviews/]

### D4-02: 承認された指摘が計画書に反映されている
- **severity**: blocker
- **verify_type**: automated + inspection
- **verification**:
  1. レビュー結果から承認済み（consensus / approved）の findings を抽出する
  2. 各 finding に対応する計画書の変更を `git log -p -- docs/plans/*-plan.md` または計画書本文の該当記述で照合する
  3. 対応する変更が見つからない finding をリストアップする
  4. 却下された finding には却下理由が記録されているか確認する
- **pass_condition**: 手順3のリストが0件、かつ却下理由なしの却下 finding が0件
- **fail_diagnosis_hint**: 未反映の finding ID を特定し、計画書の該当タスクを確認する。テストケース定義への波及が必要な finding は `docs/plans/*-test-cases.md` 側の更新漏れも確認する
- **depends_on_artifacts**: [artifacts/reviews/, docs/plans/*-plan.md]

### D4-03: Evidence Plan 再評価の要否判定が記録されている
- **severity**: quality
- **verify_type**: inspection
- **verification**:
  1. Phase 1 Audit Gate 完了時点の設計書 hash と現時点の設計書 hash を比較した記録を探す
  2. hash が変化している場合、Evidence Plan 再評価が必要と判定された記録があるか確認する
  3. hash が変化していない場合、再評価不要と判定された記録があるか確認する
- **pass_condition**: 手順1の hash 比較結果と、手順2または手順3の判定結果の両方が記録されていること
- **fail_diagnosis_hint**: 判定記録が無い場合、Phase 2 のレビュー修正で設計書が変更されたかを `git log --oneline -- docs/plans/*-design.md` で確認し、変更があれば Evidence Plan の再評価を実行する
- **depends_on_artifacts**: [docs/plans/*-design.md, docs/plans/]

### D4-04: 修正後の計画書が git commit 済みで handover が実行されている
- **severity**: blocker
- **verify_type**: automated
- **verification**:
  1. `git status --porcelain -- docs/plans/` を実行し、計画書とテストケース定義が未コミット変更リストに含まれないことを確認する
  2. `Glob(".agents/handover/**/project-state.json")` と `Glob(".agents/handover/**/handover.md")` で handover 成果物を検索する
  3. project-state.json の `phase_summaries` に `plan-review` キーが存在するか確認する
- **pass_condition**: 手順1の出力に `*-plan.md` と `*-test-cases.md` のパスが含まれないこと、手順2の各 Glob 結果が1件以上、手順3のキーが存在すること
- **fail_diagnosis_hint**: 計画書が未コミットなら `git add` + `git commit` が抜けている。handover 成果物が無い場合は Phase 4 完了時の `/handover` 実行を確認する
- **depends_on_artifacts**: [docs/plans/*-plan.md, .agents/handover/]
- **forward_check**: Phase 5 (Execute) の入力としてレビュー通過済み計画書パスが渡される

## Observation Collection

phase-auditor は verdict 出力時に observations[] を必ず含めること。
PASS 判定の criteria でも quality/warning レベルの所見があれば記録する。
observations は project-state.json の phase_observations[] に蓄積される。
