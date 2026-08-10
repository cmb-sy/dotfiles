---
phase: 1
name: design
max_retries: 3
audit: required
---

## Criteria

### D1-01: 設計書ファイルが存在し必須セクションを含む
- **severity**: blocker
- **verify_type**: automated + inspection
- **verification**:
  1. `Glob("docs/plans/*-design.md")` で設計書を検索する
  2. 要件・アーキテクチャ・データフロー・エラーハンドリング・テスト方針の見出しが存在するか `Grep` で確認する
- **pass_condition**: Glob 結果が1件以上、かつ必須見出しが全て存在すること
- **fail_diagnosis_hint**: Phase 1 Executor が設計書を docs/plans/ に出力しているか、見出し名が SKILL.md の設計書構造と一致しているかを確認する
- **depends_on_artifacts**: [docs/plans/]
- **forward_check**: Phase 2 (Spec Review) の入力として設計書パスが渡される

### D1-02: 要件が検証可能なレベルまで具体化されている
- **severity**: blocker
- **verify_type**: inspection
- **verification**:
  1. 設計書の要件セクションを読み、各要件に受け入れ条件（何をもって完了とするか）が記述されているか確認する
  2. 「適切に」「柔軟に」など検証不能な形容だけの要件が無いか確認する
- **pass_condition**: 全要件に検証可能な受け入れ条件があること。検証不能な要件が0件
- **fail_diagnosis_hint**: 曖昧な要件を列挙し、Phase 1 の brainstorming 記録から具体値を補う
- **depends_on_artifacts**: [docs/plans/*-design.md]

### D1-03: 設計書内のファイルパス・シンボルがコードベースに実在する
- **severity**: blocker
- **verify_type**: automated
- **verification**:
  1. 設計書からファイルパスを正規表現で抽出する
  2. 各パスを `Glob` で存在確認する（新規作成予定のパスは「新設」表記があれば除外）
- **pass_condition**: 新設表記のない全パスが実在すること
- **fail_diagnosis_hint**: 存在しないパスがタイポか削除済みかを git log で確認する
- **depends_on_artifacts**: [docs/plans/*-design.md]

### D1-04: 採らなかった案が1件以上記録されている
- **severity**: quality
- **verify_type**: inspection
- **verification**: 設計書に代替案セクションがあり、各案に「案」「採らなかった理由」の2要素が記述されているか確認する
- **pass_condition**: 代替案が1件以上、各案に理由があること
- **fail_diagnosis_hint**: brainstorming で提示した複数アプローチを設計書に転記する
- **depends_on_artifacts**: [docs/plans/*-design.md]

## Observation Collection

phase-auditor は verdict 出力時に observations[] を必ず含めること。
PASS 判定の criteria でも quality/warning レベルの所見があれば記録する。
observations は project-state.json の phase_observations[] に蓄積される。
