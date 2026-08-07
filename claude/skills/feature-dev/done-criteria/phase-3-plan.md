---
phase: 3
name: plan
max_retries: 3
audit: required
---

## Criteria

### D3-01: 実装計画書とテストケース定義が存在しタスクが checkbox 形式である
- **severity**: blocker
- **verify_type**: automated
- **verification**:
  1. `Glob("docs/plans/*-plan.md")` と `Glob("docs/plans/*-test-cases.md")` で成果物を検索する
  2. 計画書のタスク行を `Grep("^- \\[ \\]")` で抽出し、1件以上あるか確認する
- **pass_condition**: 2つの Glob 結果がそれぞれ1件以上、かつ checkbox 形式のタスク行が1件以上
- **fail_diagnosis_hint**: Phase 3 Executor（superpowers:writing-plans）が docs/plans/ に両ファイルを出力しているか確認する。タスクが checkbox 以外の箇条書きで書かれている場合は writing-plans のフォーマットに従っていない
- **depends_on_artifacts**: [docs/plans/]

### D3-02: 各タスクに Files・テスト手順・コミット手順が記述されている
- **severity**: blocker
- **verify_type**: inspection
- **verification**:
  1. 計画書から全タスクを列挙する
  2. 各タスクに変更対象ファイルの記述（Files セクションまたはファイルパスの明示）があるか確認する
  3. 各タスクに実行するテストコマンドの記述があるか確認する
  4. 各タスクにコミット手順（`git commit` を含むコマンドまたはコミットメッセージ）があるか確認する
  5. 手順2-4のいずれかが欠落したタスクをリストアップする
- **pass_condition**: 手順5のリストが0件
- **fail_diagnosis_hint**: 欠落項目のあるタスク ID を特定し、設計書の該当要件から変更対象ファイルを、`docs/plans/*-test-cases.md` から対応テストを引き当てて補完する
- **depends_on_artifacts**: [docs/plans/*-plan.md]

### D3-03: 計画書内のファイルパスが実在する
- **severity**: blocker
- **verify_type**: automated
- **verification**:
  1. 計画書からファイルパスを正規表現で抽出する
  2. 各パスを `Glob` で存在確認する（Create / 新規 と明記されたパスは除外する）
- **pass_condition**: Create / 新規 表記のない全パスが実在すること。不在パスが0件
- **fail_diagnosis_hint**: 不在パスがタイポか、新規作成対象で表記が抜けているかを切り分ける。削除済みファイルの場合は `git log --diff-filter=D -- <path>` で確認する
- **depends_on_artifacts**: [docs/plans/*-plan.md]

### D3-04: 設計書の全要件がいずれかのタスクにマップされる
- **severity**: blocker
- **verify_type**: inspection
- **verification**:
  1. 設計書の要件セクションから全要件を列挙する
  2. 計画書の全タスクを列挙する
  3. 各要件に対し、それを実現するタスクが1件以上存在するか照合する
  4. 対応タスクが存在しない要件をリストアップする
  5. 逆方向に、設計書のどの要件にも対応しないタスク（スコープ外の追加実装）をリストアップする
- **pass_condition**: 手順4のリストが0件、かつ手順5のリストが0件
- **fail_diagnosis_hint**: 未カバーの要件には計画書へのタスク追加が必要。要件とタスク ID の対応表を作成して漏れを可視化する。スコープ外タスクは設計書に要件として追記するか計画から削除する
- **depends_on_artifacts**: [docs/plans/*-design.md, docs/plans/*-plan.md]

### D3-05: 計画書とテストケース定義が git commit 済み
- **severity**: blocker
- **verify_type**: automated
- **verification**:
  `git status --porcelain -- docs/plans/` を実行し、計画書とテストケース定義が未コミット変更リストに含まれないことを確認する。
- **pass_condition**: `git status --porcelain` の出力に `*-plan.md` と `*-test-cases.md` のパスが含まれないこと
- **fail_diagnosis_hint**: 未コミットの場合は Phase 3 Executor の最終ステップでコミット処理が実行されているか確認する。自動遷移条件が「計画書がコミット済み」であるため未コミットでの遷移は無効
- **depends_on_artifacts**: [docs/plans/*-plan.md, docs/plans/*-test-cases.md]
- **forward_check**: Phase 4 (Plan Review) の入力として計画書パスが渡される

## Observation Collection

phase-auditor は verdict 出力時に observations[] を必ず含めること。
PASS 判定の criteria でも quality/warning レベルの所見があれば記録する。
observations は project-state.json の phase_observations[] に蓄積される。
