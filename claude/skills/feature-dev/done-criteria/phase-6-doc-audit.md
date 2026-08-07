---
phase: 6
name: doc-audit
max_retries: 2
audit: required
---

## Criteria

### D6-01: 影響ドキュメントの検出が実行され検出結果ファイルが存在する
- **severity**: blocker
- **verify_type**: automated
- **verification**:
  1. `Glob("**/doc-audit-report.json")` で検出結果ファイルを検索する
  2. 検出結果ファイルを読み取り、finding カテゴリのキー（`broken_deps`, `dead_links`, `orphaned_docs`, `stale_signals`, `coherence`, `missing_documentation` 等）が存在するか確認する
  3. 検出結果ファイルまたは実行ログに、実行スコープ（A: 実装変更の影響のみ / B: プロジェクト全体）とスコープに対応する起動引数（A: `--range`、B: `--full`）が記録されているか確認する
  4. 全カテゴリの finding が0件の場合、走査対象となった md ファイル数が記録されており「走査した結果0件」と「未走査」が区別できるか確認する
- **pass_condition**: 手順1の Glob 結果が1件以上、手順2のカテゴリキーが1つ以上存在し、手順3のスコープと起動引数が記録されており、かつ（finding が1件以上）または（手順4の走査対象 md ファイル数が1件以上）
- **fail_diagnosis_hint**: 検出結果ファイルが無い場合、Layer 1 の doc-audit.sh が実行されていない。走査対象ファイル数が0の場合は `--range` が空のコミット範囲を指している可能性があるため `git log --oneline <range>` で範囲を確認する。スコープ記録が無い場合は Phase 6 冒頭のユーザー確認（A / B）が実施されていない
- **depends_on_artifacts**: [doc-audit-report.json]

### D6-02: 検出された全 finding が更新済みまたはスキップ理由つきで処理されている
- **severity**: blocker
- **verify_type**: automated + inspection
- **verification**:
  1. 検出結果ファイルの全カテゴリから finding を ID 付きで列挙する
  2. 各 finding の status（`updated` / `skipped` / 未設定）を読み取る
  3. `updated` の finding について、対象 md の該当記述または `git log -p -- <対象 md パス>` で修正が反映されているか照合する
  4. `skipped` の finding について、ユーザーがスキップを選択した理由の記述が存在するか確認する
  5. status 未設定の finding、手順3で修正が照合できない finding、手順4で理由なしの `skipped` finding をリストアップする
- **pass_condition**: 手順5のリストが0件
- **fail_diagnosis_hint**: status 未設定の finding ID を特定し、Layer 3 の修正実行が中断していないか確認する。修正が照合できない場合は finding の対象パスと実ファイルのパスがずれていないか確認する。理由なしの `skipped` は、ユーザーがスキップを選択した時点の判断を検出結果ファイルに追記する
- **depends_on_artifacts**: [doc-audit-report.json, docs/]

### D6-03: 更新した md の depends-on が実在パスを指している
- **severity**: quality
- **verify_type**: automated
- **verification**:
  1. `git diff --name-only <artifacts.branch_base>..HEAD -- "*.md"` で本フェーズまでに作成/更新された md を列挙し、検出結果ファイルの修正対象と突き合わせる
  2. 各 md の YAML frontmatter の `depends-on` に列挙されたファイルパス・glob を抽出する
  3. 各パス・glob を `Glob` で存在確認する
- **pass_condition**: 手順3で解決結果が0件となるパス・glob が0件
- **fail_diagnosis_hint**: 解決できないパスがタイポか、ファイル移動・削除に追随していないかを `git log --diff-filter=DR -- <path>` で切り分ける。glob が広すぎる場合は doc-check の依存グラフが過剰に発火するため範囲を絞る
- **depends_on_artifacts**: [docs/, doc-audit-report.json]
- **forward_check**: Phase 7 (Smoke Test) / Phase 8 (Code Review) へは処理済み finding と更新済みドキュメントを含む状態が渡される

## Observation Collection

phase-auditor は verdict 出力時に observations[] を必ず含めること。
PASS 判定の criteria でも quality/warning レベルの所見があれば記録する。
observations は project-state.json の phase_observations[] に蓄積される。
