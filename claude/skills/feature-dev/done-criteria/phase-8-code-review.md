---
phase: 8
name: code-review
max_retries: 3
audit: required
---

## Criteria

### D8-01: レビューが全7観点で実行され findings が回収されている
- **severity**: blocker
- **verify_type**: automated
- **verification**:
  1. レビュー結果ファイル（`artifacts/reviews/phase-8-review.json` またはレビューログ）を読み取る
  2. simplify, code-quality, code-security, code-performance, code-test, ai-antipattern, code-impact の7観点それぞれの実行記録が存在するか確認する（`--codex` 指定時に追加される codex 観点は判定に含めない）
  3. `--swarm` 有効時は6エージェント + オーケストレーターが別途実行する simplify の構成であり、判定対象は同じ7観点とする
  4. 記録のある全観点について findings リストが返却されているか確認する。エージェントエラーで findings が空扱いになった観点は「[category] エージェントエラー」の注記が記録されているか確認する
- **pass_condition**: 手順2の7観点すべての実行記録が存在し、手順4で findings 未返却かつエラー注記もない観点が0件
- **fail_diagnosis_hint**: 欠落している観点を特定し、/code-review の起動引数を確認する。観点の指定漏れかレビューエージェントの中断かを切り分ける。`--swarm` 有効時に simplify が欠落している場合は、チーム外で Skill tool から実行する手順が飛ばされている
- **depends_on_artifacts**: [artifacts/reviews/]

### D8-02: 承認された findings の修正が適用され修正後の検証が PASS
- **severity**: blocker
- **verify_type**: automated + inspection
- **verification**:
  1. レビューレポートに対するユーザー選択の記録（`all` / `none` / 指摘番号）が存在するか確認する
  2. 手順1の選択から承認された findings を集合として抽出する。選択が `none` の場合は空集合となる
  3. 承認された各 finding の対象ファイル該当箇所を `Read` で読み取り、指摘内容に対応する修正が適用されているか確認する。適用が確認できない finding をリストアップする
  4. 承認 findings が1件以上ある場合、/code-review の Verify ステップで実行された linter・テストの実行コマンド文字列と出力サマリー（exit code, failed 件数）が記録されているか確認する
- **pass_condition**: 手順1の選択記録が存在し、手順3のリストが0件、かつ（承認 findings が空集合であること、または手順4の全コマンドの exit code が 0 で failed 件数が 0 であること）
- **fail_diagnosis_hint**: 手順1の選択記録が無い場合、findings の提示とユーザー選択のステップが実行されていない（findings 0件の場合もその旨の記録が必要）。未適用の finding は対象ファイルの該当行と `git log --oneline` の修正コミットを突き合わせ、適用漏れか別の形で反映済みかを切り分ける。テスト失敗は最大2回までリトライし、それでも失敗なら PAUSE とする
- **depends_on_artifacts**: [artifacts/reviews/, src/, tests/]

### D8-03: コード変更があった場合 Re-gate と re-review が最終修正以降に完了している
- **severity**: blocker
- **verify_type**: automated
- **verification**:
  1. D8-02 手順2の承認 findings が空集合か1件以上かを判定する
  2. 空集合の場合、Phase 8 でコード変更は発生しておらず Re-gate + Re-review は不要である。`git status --porcelain` が空であることを併せて確認し、本基準を N/A として verdict に記録する
  3. 1件以上の場合、レビュー修正を含む最終コミットのハッシュと committer date を `git log -1 --format='%H %cI'` で特定する
  4. 手順3のコミット以降に以下がすべて記録されているか確認する:
     a. Phase 5 Audit Gate 再実行（full mode）の PASS verdict
     b. `--doc` 有効時のみ: Phase 6 Re-gate の実行記録（`doc-audit.sh --range <fix-commit>..HEAD` の出力、または影響なしの判定記録）
     c. `--smoke` 有効時のみ: Phase 7 Audit Gate 再実行の PASS verdict
     d. /code-review 再実行の記録で findings が0件、または残 findings 全件がユーザー却下として記録されている
  5. 無効なフラグに対応する Re-gate（`--doc` 未指定時の Phase 6 Re-gate 等）が実行されていないことは FAIL 事由としない
- **pass_condition**: 手順2で N/A が記録されていること、または手順4の a〜d（フラグで無効な b・c を除く）すべてが手順3のコミット以降の記録として存在すること
- **fail_diagnosis_hint**: Re-gate の記録が無い場合、修正適用後に Phase 8 Audit Gate へ直行しており Re-review ループが飛ばされている。Re-gate が FAIL のままなら修正 → Phase 5 Re-gate 再実行のループを回す。re-review が3回連続で findings を出す場合は PAUSE して設計の根本見直しを促す。Re-gate の attempt は Phase 8 の attempt とは独立で、ループ開始時にリセットされる
- **depends_on_artifacts**: [artifacts/reviews/, src/, tests/]

### D8-04: impact の severity high 以上の findings がユーザー判断を経ている
- **severity**: blocker
- **verify_type**: automated + inspection
- **verification**:
  1. レビュー結果から category: code-impact かつ severity が high または critical の findings を抽出する
  2. 抽出結果が0件の場合、本基準は PASS とする
  3. 1件以上の場合、各 finding について以下のいずれかの記録があるか確認する:
     a. 修正済み: 対応するコード変更がコミットに含まれる
     b. ユーザー明示承認の延期: ユーザーの承認発言と承認理由が記録されている
     c. ユーザー承認の却下: 誤検出の根拠がユーザーに提示され、ユーザーが却下を承認している
  4. オーケストレーターの自己判断で延期・却下された findings（ユーザー確認の記録がないもの）をリストアップする
- **pass_condition**: 手順3の全 findings が a / b / c のいずれかに該当し、手順4のリストが0件
- **fail_diagnosis_hint**: ユーザー未確認の findings を特定し、PAUSE して修正・延期・却下の判断を求める。延期の場合は承認理由まで記録されているかを確認する（理由の記録がない延期は本基準では未判断として扱う）
- **depends_on_artifacts**: [artifacts/reviews/]

### D8-05: レビュー修正がコミット済みで handover が実行されている
- **severity**: blocker
- **verify_type**: automated
- **verification**:
  1. `git status --porcelain` を実行し、未コミット変更が0件であることを確認する
  2. `git branch --show-current` で現ブランチ名を取得し、`Glob(".agents/handover/<現ブランチ名>/**/project-state.json")` と `Glob(".agents/handover/<現ブランチ名>/**/handover.md")` で handover 成果物を検索する
  3. 手順2の project-state.json の `phase_summaries` に `code-review` キーが存在するか確認する
  4. `git log -1 --format=%cI` でフェーズ完了コミットの committer date を取得し、project-state.json の `generated_at` がそれ以降であることを確認する
- **pass_condition**: 手順1の出力行数が0、手順2の各 Glob 結果が1件以上、手順3のキーが存在し、手順4で `generated_at` >= フェーズ完了コミットの committer date
- **fail_diagnosis_hint**: 未コミット変更があれば `git add` + `git commit` が抜けている。現ブランチ配下に handover 成果物が無い場合は Phase 8 完了時の `/handover` 実行を確認する（他ブランチ配下の成果物は判定に使わない）。`phase_summaries` にキーが無い場合は project-state.json の `pipeline` フィールド未設定で Phase Summary 生成がスキップされた可能性がある。手順4が不成立なら handover がレビュー修正より前に実行された古い成果物である
- **depends_on_artifacts**: [.agents/handover/]
- **forward_check**: Phase 9 (Test Review) / Phase 10 (Integrate) の入力としてレビュー修正済みコードとブランチ名が渡される

## Observation Collection

phase-auditor は verdict 出力時に observations[] を必ず含めること。
PASS 判定の criteria でも quality/warning レベルの所見があれば記録する。
observations は project-state.json の phase_observations[] に蓄積される。
