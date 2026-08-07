---
phase: 5
name: execute
max_retries: 3
audit: required
---

## Criteria

### D5-01: 計画書の全タスクが完了チェック済みでコード変更がコミットされている
- **severity**: blocker
- **verify_type**: automated
- **verification**:
  1. `Grep("^- \\[ \\]", "docs/plans/*-plan.md")` で未完了 checkbox のタスク行を抽出する
  2. `Grep("^- \\[x\\]", "docs/plans/*-plan.md")` で完了 checkbox のタスク行を抽出し、1件以上あるか確認する
  3. `git status --porcelain` を実行し、実装対象ファイル（テストコードを含む）が未コミット変更リストに含まれないことを確認する
- **pass_condition**: 手順1の抽出結果が0件、手順2の抽出結果が1件以上、手順3の出力に実装対象ファイルのパスが含まれないこと
- **fail_diagnosis_hint**: 未完了 checkbox が残る場合、実装漏れかチェック更新漏れかを `git log --oneline` の実装コミットと突き合わせて切り分ける。手順2が0件なら計画書のタスク表記が checkbox 形式でない。手順3で未コミットが残る場合は各タスクのコミット手順が実行されていない
- **depends_on_artifacts**: [docs/plans/*-plan.md]

### D5-02: 全テストが PASS しコマンド出力の証跡がある
- **severity**: blocker
- **verify_type**: automated
- **verification**:
  1. プロジェクトのテストコマンド（`npm test`, `cargo test`, `pytest`, `go test ./...`, `bats test/` 等）を package.json / Cargo.toml / go.mod / Makefile / CLAUDE.md から特定する
  2. 特定したテストコマンドを実行し、exit code とテスト結果サマリー（total, passed, failed, skipped）を記録する
  3. 記録した実行コマンド文字列と出力サマリーを audit verdict に含める
- **pass_condition**: 手順2の exit code が 0、failed テスト数が 0、かつ手順3で実行コマンドと出力サマリーの両方が verdict に記録されていること
- **fail_diagnosis_hint**: 失敗したテスト名とエラーメッセージを確認する。既存テストの退行か新規テストの初回失敗かは `git diff --name-only -- tests/` で切り分ける。テストコマンドが特定できない場合は計画書の各タスクに記述されたテスト手順を参照する
- **depends_on_artifacts**: [docs/plans/*-plan.md, tests/]

### D5-03: linter・型チェックが PASS
- **severity**: blocker
- **verify_type**: automated
- **verification**:
  1. プロジェクトの linter / 型チェッカー / フォーマッター（`npm run lint`, `eslint`, `tsc --noEmit`, `ruff check`, `cargo clippy`, `shellcheck` 等）を設定ファイルから特定する
  2. 特定した各コマンドを実行し、exit code と error レベルの指摘件数を記録する
  3. 記録した実行コマンド文字列と出力を audit verdict に含める
- **pass_condition**: 手順2の全コマンドの exit code が 0 かつ error レベルの指摘が0件、かつ手順3で実行コマンドと出力が verdict に記録されていること
- **fail_diagnosis_hint**: 指摘のファイルパスと行番号を確認する。型エラーは型定義の不整合、lint エラーは規約違反を確認し、`--fix` で自動修正可能か判定する。該当するツールがプロジェクトに存在しない場合はその事実を verdict に記録する
- **depends_on_artifacts**: [src/, artifacts/lint/]

### D5-04: Evidence Plan が設計書の変更に追随している
- **severity**: blocker
- **verify_type**: automated
- **verification**:
  1. `Glob("docs/plans/*evidence-plan.md")` で Evidence Plan を検索し、その初回コミットを `git log --format=%H -- <evidence-plan パス>` の最終行で特定する
  2. `git log --oneline <初回コミット>..HEAD -- docs/plans/*-design.md` で、Evidence Plan 生成以降の設計書変更コミット件数を数える
  3. 手順2が0件の場合、Evidence Plan の据え置きが正であり追加検証は不要と判定する
  4. 手順2が1件以上の場合、最新の設計書変更コミットのハッシュを取得し、`git log --oneline <最新の設計書変更コミット>..HEAD -- <evidence-plan パス>` で Evidence Plan の更新コミット件数を数える
- **pass_condition**: 手順1の Glob 結果が1件以上、かつ（手順2が0件）または（手順4の件数が1件以上）
- **fail_diagnosis_hint**: 手順1で Evidence Plan が見つからない場合、Phase 1 Audit Gate での初回生成が実行されていない。手順4が0件の場合、Phase 4 Audit Gate 完了後に実行すべき Evidence Plan 再評価が未実施か、再評価の結果が「変更不要」でもコミットされていない。後者なら再評価結果を Evidence Plan に追記してコミットする
- **depends_on_artifacts**: [docs/plans/*-design.md, docs/plans/*evidence-plan.md]

### D5-05: 計画外の変更（スコープクリープ）が無い
- **severity**: quality
- **verify_type**: inspection
- **verification**:
  1. 計画書の全タスクから変更対象ファイル（Files セクションまたは本文中のファイルパス）を集合として列挙する
  2. `git diff --name-only <artifacts.branch_base>..HEAD` で実際に変更されたファイルの集合を取得する
  3. 手順2の集合から手順1の集合を差し引き、計画書に記載のない変更ファイルをリストアップする
  4. 手順3の各ファイルについて、既存タスクの実装に付随して必要となった変更（import 追加、型定義の追随、テストヘルパーの共通化等）か、計画に無い機能追加かを diff 内容で判定する
- **pass_condition**: 手順4で「計画に無い機能追加」と判定されたファイルが0件
- **fail_diagnosis_hint**: 計画外の機能追加と判定された変更は、計画書へのタスク追記か、当該変更の revert かをユーザーに確認する。付随変更の場合は計画書の Files 記述に追記して以降の照合対象に含める
- **depends_on_artifacts**: [docs/plans/*-plan.md, src/]
- **forward_check**: Phase 6 (Doc Audit) / Phase 7 (Smoke Test) / Phase 8 (Code Review) の入力としてコミット済みコードと変更ファイル一覧が渡される

## Observation Collection

phase-auditor は verdict 出力時に observations[] を必ず含めること。
PASS 判定の criteria でも quality/warning レベルの所見があれば記録する。
observations は project-state.json の phase_observations[] に蓄積される。
