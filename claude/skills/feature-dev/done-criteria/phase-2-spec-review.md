---
phase: 2
name: spec-review
max_retries: 3
audit: required
---

## Criteria

### D2-01: レビューが全4観点で実行され findings が回収されている
- **severity**: blocker
- **verify_type**: automated
- **verification**:
  1. レビュー結果ファイル（`artifacts/reviews/phase-2-review.json` またはレビューログ）を読み取る
  2. requirements, design-judgment, feasibility, consistency の4観点それぞれの実行記録が存在するか確認する（`--ui` 指定時の追加観点は判定に含めない）
  3. 記録のある全観点について findings リストが返却されているか確認する（未返却・実行途中終了の観点を検出する）
- **pass_condition**: 手順2の4観点すべての実行記録が存在し、手順3で findings 未返却の観点が0件
- **fail_diagnosis_hint**: 欠落している観点を特定し、/spec-review の起動引数を確認する。観点の指定漏れかレビューエージェントの中断かを切り分ける
- **depends_on_artifacts**: [artifacts/reviews/]

### D2-02: 承認された指摘が設計書に反映されている
- **severity**: blocker
- **verify_type**: automated + inspection
- **verification**:
  1. レビュー結果から承認済み（consensus / approved）の findings を抽出する
  2. 各 finding に対応する設計書の変更を `git log -p -- docs/plans/*-design.md` または設計書本文の該当記述で照合する
  3. 対応する変更が見つからない finding をリストアップする
  4. 却下された finding には却下理由が記録されているか確認する
- **pass_condition**: 手順3のリストが0件、かつ却下理由なしの却下 finding が0件
- **fail_diagnosis_hint**: 未反映の finding ID を特定し、設計書の該当セクションを確認する。修正が反映されていない場合は /spec-review のフィードバックループが完了しているか確認する
- **depends_on_artifacts**: [artifacts/reviews/, docs/plans/*-design.md]

### D2-03: 反映後の設計書が自己矛盾していない
- **severity**: quality
- **verify_type**: inspection
- **verification**:
  1. 設計書の要件セクションとアーキテクチャセクションを並べ、同一コンポーネント名・ファイルパス・データ型が一致しているか照合する
  2. データフローの記述が要件で定義した入出力と一致しているか確認する
  3. レビュー修正で片方のセクションだけ更新され、他セクションに旧記述が残っていないか確認する
  4. 未解決マーカー（TODO / TBD / ???）が残っていないか `Grep` で確認する
- **pass_condition**: 手順1-3で不一致が0件、手順4で未解決マーカーが0件
- **fail_diagnosis_hint**: 不一致箇所の両方の記述を並べ、`git log -p -- docs/plans/*-design.md` で直近のレビュー修正コミットからどちらが新しい意図かを追跡する
- **depends_on_artifacts**: [docs/plans/*-design.md]

### D2-04: 修正後の設計書が git commit 済みで handover が実行されている
- **severity**: blocker
- **verify_type**: automated
- **verification**:
  1. `git status --porcelain -- docs/plans/*-design.md` を実行し、設計書が未コミット変更リストに含まれないことを確認する
  2. `git branch --show-current` で現ブランチ名を取得し、`Glob(".agents/handover/<現ブランチ名>/**/project-state.json")` と `Glob(".agents/handover/<現ブランチ名>/**/handover.md")` で handover 成果物を検索する
     - チーム実行（`--swarm`）では handover がブランチ分離を適用しないため、`.agents/handover/<team-name>/**/project-state.json` と `.agents/handover/<team-name>/**/handover.md` も探索対象に含め、いずれかの経路で見つかれば成立とする
  3. 手順2の project-state.json の `phase_summaries` に `spec-review` キーが存在するか確認する
  4. `git log -1 --format=%cI -- docs/plans/*-design.md` でフェーズ完了コミットの committer date を取得し、project-state.json の `generated_at` がそれ以降であることを確認する
- **pass_condition**: 手順1の出力行数が0、手順2の各 Glob 結果が1件以上、手順3のキーが存在し、手順4で `generated_at` >= フェーズ完了コミットの committer date
- **fail_diagnosis_hint**: 設計書が未コミットなら `git add` + `git commit` が抜けている。現ブランチ配下に handover 成果物が無い場合は Phase 2 完了時の `/handover` 実行を確認する（他ブランチ配下の成果物は判定に使わない）。`phase_summaries` にキーが無い場合は project-state.json の `pipeline` フィールド未設定で Phase Summary 生成がスキップされた可能性がある。手順4が不成立なら handover が Phase 2 のレビュー修正より前に実行された古い成果物である
- **depends_on_artifacts**: [docs/plans/*-design.md, .agents/handover/]
- **forward_check**: Phase 3 (Plan) の入力としてレビュー通過済み設計書パスが渡される

## Observation Collection

phase-auditor は verdict 出力時に observations[] を必ず含めること。
PASS 判定の criteria でも quality/warning レベルの所見があれば記録する。
observations は project-state.json の phase_observations[] に蓄積される。
