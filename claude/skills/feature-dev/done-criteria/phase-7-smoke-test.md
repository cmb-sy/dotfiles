---
phase: 7
name: smoke-test
max_retries: 3
audit: required
---

## Criteria

### D7-01: smoke-test の実行証跡が存在し所定フォーマットに準拠している
- **severity**: blocker
- **verify_type**: automated
- **verification**:
  1. 作業ディレクトリに `smoke-test-report.md` が存在するか確認する
  2. レポートのヘッダに `Server:`（起動コマンドとポート）と `Diff Base:` のフィールドが記入されているか確認する
  3. レポートの Step 2 テーブルに「シナリオ」「観点」「結果」「スクリーンショット」の各列が存在し、データ行が1行以上あるか確認する
  4. `Glob("smoke-*.png")` でスクリーンショットが1枚以上存在するか確認する
  5. Step 2 テーブルの「スクリーンショット」列が参照するファイル名が、手順4で実在を確認したファイルと一致するか照合する
  6. Verification Notes の `Adversarial probe executed` が `yes` として記録されているか確認する
- **pass_condition**: 手順1のファイルが存在し、手順2の両フィールドが空でなく、手順3の4列すべてとデータ行1行以上が存在し、手順4が1件以上、手順5で不在ファイルを参照する行が0件、手順6が `yes` であること
- **fail_diagnosis_hint**: レポート未存在なら smoke-test スキルが実行されていない。既存テストスイート（rspec, jest 等）の実行で代替されていた場合それは無効な実行であり、smoke-test を正しく再実行する必要がある。スクリーンショット未存在は browser-use CLI が起動できていない可能性があり、環境問題であれば PAUSE としてユーザーに報告する。adversarial probe 未実行は smoke-test 側の総合ステータス判定で FAIL 扱いとなるため、境界値・異常系のシナリオを追加して再実行する
- **depends_on_artifacts**: [smoke-test-report.md, smoke-*.png]

### D7-02: 全ステップが PASS し、FAIL は修正→再実行のループが完了している
- **severity**: blocker
- **verify_type**: automated
- **verification**:
  1. レポートヘッダの `Status:` フィールドを読み取る
  2. Step 2 テーブルの各シナリオの「結果」列から FAIL 行を抽出する
  3. Step 3（VRT）の記録が `SKIP` / `PASS` / `DIFF_DETECTED` のいずれであるか読み取る。`DIFF_DETECTED` の場合、差分がベースライン更新またはユーザー承認で解消された記録があるか確認する
  4. Step 4 の Implementation Failures テーブルの行数を数える（`Flaky Tests` テーブルの行は数えない）
  5. FAIL の記録がある場合、その後に修正コミット（`git log --oneline` の該当変更）と再実行の記録が存在し、最終試行が PASS であるか確認する
- **pass_condition**: 手順1の `Status:` が PASS、手順2の FAIL 行が0件、手順3が `SKIP` または `PASS`（`DIFF_DETECTED` の場合は解消記録あり）、手順4の Implementation Failures が0行、手順5で FAIL 後に再実行記録のないケースが0件
- **fail_diagnosis_hint**: FAIL ステップ名とエラーを確認し、ブラウザ操作の失敗（セレクタ不一致、タイムアウト）かアプリケーションエラー（HTTP 5xx、例外）かを切り分ける。アプリケーションバグの修正は最大2回まで試行し、修正不能なら PAUSE とする。VRT 差分が意図した変更である場合はベースライン更新の判断をユーザーに確認する。flaky のみの検出は smoke-test 側の判定で PASS 扱いであり、レポートに記録されていれば本基準では FAIL としない
- **depends_on_artifacts**: [smoke-test-report.md]

### D7-03: スキップした場合はスキップ判定が記録されている
- **severity**: quality
- **verify_type**: automated
- **verification**:
  1. 本フェーズがスキップされたか実行されたかを判定する（`smoke-test-report.md` が存在すれば実行、存在しなければスキップ）
  2. 実行されている場合、本基準は対象外（N/A）として verdict に記録する
  3. スキップされている場合、`--smoke` 未指定であることと、設計書に UI 関連キーワード（画面 / UI / ページ / フォーム / frontend / component / view / page / form）が含まれないことの両方が判定根拠として記録されているか確認する
  4. 設計書に UI 関連キーワードが含まれる場合、自動有効化の提案に対してユーザーがスキップを選択した記録が存在するか確認する
- **pass_condition**: 手順2で N/A と記録されていること、または手順3の両根拠が記録されていること、または手順4のユーザー判断が記録されていること
- **fail_diagnosis_hint**: スキップ根拠が記録されていない場合、設計書を `Grep` で UI 関連キーワード走査し、ヒットするならユーザーに smoke-test 実行の要否を確認する。ヒットしないならスキップ判定とその根拠を記録して Phase 8 へ進む
- **depends_on_artifacts**: [docs/plans/*-design.md, smoke-test-report.md]

### D7-04: 設計書由来のテスト観点がシナリオに対応している
- **severity**: blocker
- **verify_type**: inspection
- **verification**:
  1. 設計書（`--design` で渡されたパス）の「テスト観点」または「Test Perspectives」セクションから各観点を列挙する
  2. 設計書の Investigation Record 内の Must-Verify Checklist から各項目を列挙する
  3. レポートの Step 2 テーブルと Evidence Log からシナリオを列挙する
  4. 手順1・手順2の各項目に対応するシナリオが1件以上存在するか照合する
  5. 対応シナリオが存在しない観点・チェックリスト項目をリストアップする
- **pass_condition**: 手順1と手順2の列挙結果がいずれも0件（設計書に両セクションが存在しない）、または手順5のリストが0件
- **fail_diagnosis_hint**: 未対応の観点を特定し、該当する操作シナリオを追加して smoke-test を再実行する。照合対象は smoke-test が `--design` から実際に抽出する3種（テスト観点セクション / Must-Verify Checklist / Impact Analysis）に限る。設計書に両セクションが無いのに本フェーズが実行されている場合は `--smoke` の明示指定によるものであり、手順1・2が0件で PASS となる
- **depends_on_artifacts**: [docs/plans/*-design.md, smoke-test-report.md]
- **forward_check**: Phase 8 (Code Review) の入力としてスモークテスト通過済みコードが渡される

## Observation Collection

phase-auditor は verdict 出力時に observations[] を必ず含めること。
PASS 判定の criteria でも quality/warning レベルの所見があれば記録する。
observations は project-state.json の phase_observations[] に蓄積される。
