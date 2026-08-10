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
  1. Layer 1 の検出結果を次のいずれかから取得する: (a) `Glob("**/doc-audit-report.json")` で見つかる検出結果ファイル、または (b) フェーズ実行ログに記録された `doc-audit.sh --json` の JSON 出力。doc-audit.sh は JSON を標準出力に書くため、(a) が無くても (b) があれば有効な証跡として扱う
  2. 取得した JSON に finding カテゴリのキー（`broken_deps`, `dead_links`, `undeclared_deps`, `orphaned_docs`, `stale_signals` 等）が存在するか確認する
  3. JSON の `meta.scope` が `full`（スコープ B: プロジェクト全体）または `range`（スコープ A: 実装変更の影響のみ）のいずれかであり、`range` の場合は `meta.commit_range` が null でないことを確認する
  4. 全カテゴリの finding が0件の場合、`meta.total_docs_scanned` を読み取り「走査した結果0件」と「未走査」が区別できるか確認する
- **pass_condition**: 手順1で (a) または (b) のいずれかから JSON が取得でき、手順2のカテゴリキーが1つ以上存在し、手順3の `meta.scope` が `full` または `range`（`range` なら `meta.commit_range` が非 null）であり、かつ（finding が1件以上）または（手順4の `meta.total_docs_scanned` が1以上）
- **fail_diagnosis_hint**: (a) も (b) も無い場合、Layer 1 の doc-audit.sh が実行されていない。`meta.total_docs_scanned` が0の場合は `--range` が空のコミット範囲を指している可能性があるため `git log --oneline <range>` で範囲を確認する。JSON がフェーズ実行ログにしか存在しないのは doc-audit.sh がファイル出力を持たないための正常な状態であり、それ自体を FAIL としない
- **depends_on_artifacts**: [doc-audit-report.json]

### D6-02: 検出された全 finding が更新済みまたはスキップ理由つきで処理されている
- **severity**: blocker
- **verify_type**: automated + inspection
- **verification**:
  1. D6-01 で取得した Layer 1 出力の全カテゴリから finding を ID 付きで列挙し、Layer 2 エージェント群が追加した finding も統合レポートから列挙する
  2. 各 finding の status（`updated` / `skipped` / 未設定）を Layer 3 の処理記録（doc-check 実行ログまたはフェーズ実行記録）から読み取る
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
  1. 検証対象 md を次の一次ソースから決める: D6-01 で取得した Layer 1 出力の finding が指す対象 md パスのうち、status が `updated` のもの
  2. 手順1の集合に、`git status --porcelain -- "*.md"`（未コミットの作業ツリー変更）と `git diff --name-only <artifacts.branch_base>..HEAD -- "*.md"`（コミット済み変更）の**和集合**を加える。Phase 6 はドキュメントをコミットしないため、diff 側だけでは空集合になり得る
  3. 手順2の集合が空でありながら status が `updated` の finding が1件以上ある場合、検証対象の特定に失敗しているとみなす
  4. 各 md の YAML frontmatter の `depends-on` に列挙されたファイルパス・glob を抽出する
  5. 各パス・glob を `Glob` で存在確認する
- **pass_condition**: 手順3の不整合が発生しておらず、かつ手順5で解決結果が0件となるパス・glob が0件
- **fail_diagnosis_hint**: 手順3で不整合が出た場合、finding の対象パスと実ファイルのパス表記（リポジトリルート相対か絶対か）がずれている。解決できない `depends-on` パスがタイポか、ファイル移動・削除に追随していないかは `git log --diff-filter=DR -- <path>` で切り分ける。glob が広すぎる場合は doc-check の依存グラフが過剰に発火するため範囲を絞る
- **depends_on_artifacts**: [docs/, doc-audit-report.json]
- **forward_check**: Phase 7 (Smoke Test) / Phase 8 (Code Review) へは処理済み finding と更新済みドキュメントを含む状態が渡される

## Observation Collection

phase-auditor は verdict 出力時に observations[] を必ず含めること。
PASS 判定の criteria でも quality/warning レベルの所見があれば記録する。
observations は project-state.json の phase_observations[] に蓄積される。
