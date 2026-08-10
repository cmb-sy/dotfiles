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
  2. clarity, feasibility, consistency の3観点それぞれの実行記録が存在するか確認する（`--ui` 指定時の追加観点は判定に含めない）
  3. 記録のある全観点について findings リストが返却されているか確認する（未返却・実行途中終了の観点を検出する）
- **pass_condition**: 手順2の3観点すべての実行記録が存在し、手順3で findings 未返却の観点が0件
- **fail_diagnosis_hint**: 欠落している観点を特定し、/implementation-review の起動引数を確認する。consistency 観点には設計書パスが追加コンテキストとして渡されている必要がある
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
- **verify_type**: automated
- **verification**:
  1. `Glob("docs/plans/*evidence-plan.md")` で Evidence Plan を検索し、その初回コミットを `git log --format=%H -- <evidence-plan パス>` の最終行で特定する（Phase 1 Audit Gate で生成されたコミット）
  2. `git log --oneline <初回コミット>..HEAD -- docs/plans/*-design.md` で、Evidence Plan 生成以降の設計書変更コミット件数を数える
  3. 手順2の結果から再評価の要否を判定し（1件以上なら再評価必要、0件なら再評価不要）、その判定結果を audit verdict に記録する
- **pass_condition**: 手順1の Glob 結果が1件以上（0件なら FAIL）、かつ手順3の要否判定結果が verdict に記録されていること
- **fail_diagnosis_hint**: 手順1で Evidence Plan が見つからない場合、Phase 1 Audit Gate での初回生成が実行されていない。Evidence Plan の再評価自体は Phase 4 Audit Gate 完了後に実行されるため、この基準は要否判定までを検証する。再評価が実際に反映されたことの強制は Phase 5 (Execute) 側の管轄
- **depends_on_artifacts**: [docs/plans/*-design.md, docs/plans/*evidence-plan.md]

### D4-04: 修正後の計画書が git commit 済みで handover が実行されている
- **severity**: blocker
- **verify_type**: automated
- **verification**:
  1. `git status --porcelain -- docs/plans/` を実行し、計画書とテストケース定義が未コミット変更リストに含まれないことを確認する
  2. `git branch --show-current` で現ブランチ名を取得し、`Glob(".agents/handover/<現ブランチ名>/**/project-state.json")` と `Glob(".agents/handover/<現ブランチ名>/**/handover.md")` で handover 成果物を検索する
     - チーム実行（`--swarm`）では handover がブランチ分離を適用しないため、`.agents/handover/<team-name>/**/project-state.json` と `.agents/handover/<team-name>/**/handover.md` も探索対象に含め、いずれかの経路で見つかれば成立とする
  3. 手順2の project-state.json の `phase_summaries` に `plan-review` キーが存在するか確認する
  4. `git log -1 --format=%cI -- docs/plans/*-plan.md` でフェーズ完了コミットの committer date を取得し、project-state.json の `generated_at` がそれ以降であることを確認する
- **pass_condition**: 手順1の出力に `*-plan.md` と `*-test-cases.md` のパスが含まれないこと、手順2の各 Glob 結果が1件以上、手順3のキーが存在し、手順4で `generated_at` >= フェーズ完了コミットの committer date
- **fail_diagnosis_hint**: 計画書が未コミットなら `git add` + `git commit` が抜けている。現ブランチ配下に handover 成果物が無い場合は Phase 4 完了時の `/handover` 実行を確認する（他ブランチ配下の成果物は判定に使わない）。手順4が不成立なら handover が Phase 4 のレビュー修正より前に実行された古い成果物である
- **depends_on_artifacts**: [docs/plans/*-plan.md, .agents/handover/]
- **forward_check**: Phase 5 (Execute) の入力としてレビュー通過済み計画書パスが渡される

## Observation Collection

phase-auditor は verdict 出力時に observations[] を必ず含めること。
PASS 判定の criteria でも quality/warning レベルの所見があれば記録する。
observations は project-state.json の phase_observations[] に蓄積される。
