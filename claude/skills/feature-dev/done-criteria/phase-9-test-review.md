---
phase: 9
name: test-review
max_retries: 3
audit: required
---

## Criteria

### D9-01: レビューが全3観点で実行され findings が回収されている
- **severity**: blocker
- **verify_type**: automated
- **verification**:
  1. 本フェーズが実行されたかスキップされたかを判定する（`--e2e` が有効なら実行、未指定ならスキップ）。スキップの場合、本基準は N/A として verdict に記録する
  2. レビュー結果ファイル（`artifacts/reviews/phase-9-review.json` またはレビューログ）を読み取る
  3. coverage, quality, design-alignment の3観点それぞれの実行記録が存在するか確認する
  4. /test-review の起動引数に `--design <設計書パス>` が付与され、そのパスが `artifacts.design_doc` と一致するか確認する
  5. 記録のある全観点について findings リストが返却されているか確認する（未返却・実行途中終了の観点を検出する）
- **pass_condition**: 手順1で N/A と記録されていること、または（手順3の3観点すべての実行記録が存在し、手順4のパスが一致し、手順5で findings 未返却の観点が0件）
- **fail_diagnosis_hint**: 欠落している観点を特定し、/test-review の起動引数を確認する。`--design` が欠落していると design-alignment 観点が設計要件と照合できず実質的に無効な実行となるため、設計書パスを付与して再実行する
- **depends_on_artifacts**: [artifacts/reviews/, docs/plans/*-design.md]

### D9-02: 承認された findings の修正が適用され既存テストが破損していない
- **severity**: blocker
- **verify_type**: automated + inspection
- **verification**:
  1. 本フェーズがスキップされた場合、本基準は N/A として verdict に記録する
  2. レビューレポートに対するユーザー選択の記録（`all` / `none` / 指摘番号）が存在するか確認し、承認された findings を集合として抽出する
  3. 承認された各 finding の対象テストファイル該当箇所を `Read` で読み取り、指摘内容に対応する修正が適用されているか確認する。適用が確認できない finding をリストアップする
  4. 承認 findings が1件以上ある場合、プロジェクトのテストコマンドを実行し、exit code とテスト結果サマリー（total, passed, failed, skipped）を記録する
  5. 手順4の failed に、テストレビュー修正で追加・変更したテスト以外の既存テストが含まれるか確認する
- **pass_condition**: 手順1で N/A と記録されていること、または（手順2の選択記録が存在し、手順3のリストが0件、かつ 承認 findings が空集合であること、または手順4の exit code が 0 かつ failed が 0 であること）
- **fail_diagnosis_hint**: 手順2の選択記録が無い場合、findings の提示とユーザー選択のステップが実行されていない。手順5で既存テストの破損が検出された場合はリトライせず PAUSE し、破損したテスト名と影響範囲をユーザーに報告する（テスト追加が既存テストと状態を共有している可能性がある）
- **depends_on_artifacts**: [artifacts/reviews/, tests/]

### D9-03: コード変更があった場合 Re-gate と re-review が最終修正以降に完了している
- **severity**: blocker
- **verify_type**: automated
- **verification**:
  1. 本フェーズがスキップされた場合、本基準は N/A として verdict に記録する
  2. D9-02 手順2の承認 findings が空集合か1件以上かを判定する
  3. 空集合の場合、Phase 9 でコード変更は発生しておらず Re-gate + Re-review は不要である。`git status --porcelain` が空であることを併せて確認し、本基準を N/A として記録する
  4. 1件以上の場合、テストレビュー修正を含む最終コミットのハッシュと committer date を `git log -1 --format='%H %cI'` で特定する
  5. 手順4のコミット以降に以下がすべて記録されているか確認する:
     a. Phase 5 Audit Gate 再実行（full mode）の PASS verdict
     b. `--doc` 有効時のみ: Phase 6 Re-gate の実行記録（`doc-audit.sh --range <fix-commit>..HEAD` の出力、または影響なしの判定記録）
     c. `--smoke` 有効時のみ: Phase 7 Audit Gate 再実行の PASS verdict
     d. /test-review 再実行の記録で findings が0件、または残 findings 全件がユーザー却下として記録されている
  6. 無効なフラグに対応する Re-gate（`--smoke` 未指定時の Phase 7 Re-gate 等）が実行されていないことは FAIL 事由としない
- **pass_condition**: 手順1または手順3で N/A が記録されていること、または手順5の a〜d（フラグで無効な b・c を除く）すべてが手順4のコミット以降の記録として存在すること
- **fail_diagnosis_hint**: Re-gate の記録が無い場合、修正適用後に Phase 9 Audit Gate へ直行しており Re-review ループが飛ばされている。テスト修正はトレーサビリティ（設計要件とテストの対応）を壊しやすいため、Phase 5 Re-gate の要件対応基準を特に確認する。re-review が3回連続で findings を出す場合は PAUSE する
- **depends_on_artifacts**: [artifacts/reviews/, tests/]

### D9-04: スキップした場合はスキップ判定が記録されている
- **severity**: quality
- **verify_type**: automated
- **verification**:
  1. 本フェーズがスキップされたか実行されたかを判定する（`artifacts/reviews/phase-9-review.json` またはレビューログの Phase 9 実行記録が存在すれば実行、存在しなければスキップ）
  2. 実行されている場合、本基準は対象外（N/A）として verdict に記録する
  3. スキップされている場合、project-state.json の `args.e2e` が false であることと、`--e2e` 未指定によるスキップである旨がスキップ判定の根拠として記録されているか確認する
- **pass_condition**: 手順2で N/A と記録されていること、または手順3の `args.e2e` が false でスキップ根拠が記録されていること
- **fail_diagnosis_hint**: スキップ根拠が記録されていない場合、`args.e2e` の値を project-state.json で確認する。`args.e2e` が true なのにレビュー実行記録が無い場合はフェーズの取りこぼしであり、/test-review を実行して Phase 9 をやり直す
- **depends_on_artifacts**: [artifacts/reviews/, .agents/handover/]

### D9-05: テストレビュー修正がコミット済みで handover が実行されている
- **severity**: blocker
- **verify_type**: automated
- **verification**:
  1. 本フェーズがスキップされた場合、本基準は N/A として verdict に記録する
  2. `git status --porcelain -- ':/' ':(exclude,top).agents/'` を実行し、未コミット変更が0件であることを確認する。Phase 9 の変更対象はドキュメントに限定されないためリポジトリ全体を対象とし、handover 自身の書き出し先である `.agents/` のみ除外する
  3. `Glob(".agents/handover/**/project-state.json")` で現リポジトリの handover 成果物を列挙する。`--swarm` ではブランチ名も team name もディレクトリ名として当てにできないため、名前で絞り込まず列挙する
  4. 列挙された各ファイルの `generated_at` を読み、最も新しいものを対象とする。列挙結果が0件なら対象が存在しないため本基準は FAIL とする
  5. 対象が `phase_summaries` に `test-review` キーを持つことを確認する
  6. `git log -1 --format=%cI -- ':/' ':(exclude,top).agents/'` が返す日時が対象の `generated_at` 以前であることを確認する。handover 成果物のコミットを基準にすると、その直前に書かれた `generated_at` が常に古くなるため `.agents/` を除外する
- **pass_condition**: 手順1で N/A と記録されていること、または（手順2の出力行数が0、手順3の列挙結果が1件以上、手順5のキーが存在し、手順6で `generated_at` >= フェーズ完了コミットの committer date）
- **fail_diagnosis_hint**: 未コミット変更があれば `git add` + `git commit` が抜けている（`.agents/` 配下は除外済みのため、handover 成果物をコミットするかどうかは本基準の判定に影響しない）。handover 成果物が1件も無い場合は Phase 9 完了時の `/handover` 実行を確認する。`phase_summaries` にキーが無い場合は project-state.json の `pipeline` フィールド未設定で Phase Summary 生成がスキップされた可能性がある。手順6が不成立なら最新の handover がテストレビュー修正より前に実行された古い成果物である
- **depends_on_artifacts**: [.agents/handover/]
- **forward_check**: Phase 10 (Integrate) の入力としてテストレビュー済みコードとブランチ名が渡される

## Observation Collection

phase-auditor は verdict 出力時に observations[] を必ず含めること。
PASS 判定の criteria でも quality/warning レベルの所見があれば記録する。
observations は project-state.json の phase_observations[] に蓄積される。
