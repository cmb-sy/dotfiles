---
phase: 3
name: storyline-review
max_retries: 2
audit: required
---

## Criteria

### P3-01: 主張の単一性
- severity: blocker
- verify_type: manual
- verification: `storyline.md` の `## 3. 主張（Claim）` に 1 文の主張が記述されていること
- pass_condition: claim セクションが 1 文（句点 1 つ）で書かれている
- fail_diagnosis_hint: 主張を 1 文に絞り込む。複数主張があれば優先順位付け

### P3-02: 根拠の充足度
- severity: blocker
- verify_type: manual
- verification: `## 4. 根拠（Evidence）` に 2 件以上の根拠が箇条書きされていること
- pass_condition: bullet 数 ≥ 2
- fail_diagnosis_hint: 主張を支える独立した根拠を追加する

### P3-03: アクションの明示
- severity: blocker
- verify_type: manual
- verification: `## 5. アクション（Call to Action）` に「誰が」「何を」「いつ」のうち最低 2 つが含まれること
- pass_condition: subject/verb/time のうち 2 以上
- fail_diagnosis_hint: 聴衆が具体的に取るべき行動を 1 文で明記

### P3-04: 聴衆前提との整合
- severity: warning
- verify_type: manual
- verification: `brief.yaml` の `audience` に対し、storyline の専門用語が説明なしで使われていないか
- pass_condition: 未説明の専門用語が 0 件、または注釈付き
- fail_diagnosis_hint: 専門用語に注釈を加えるか、平易な表現に置き換える

### P3-05: レビュー findings の反映
- severity: blocker
- verify_type: manual
- verification: `storyline-review.md` の approved findings 全件が `storyline.md` に反映済みか
- pass_condition: 未反映 0 件
- fail_diagnosis_hint: 未反映の指摘を反映するか、却下理由をレビューに追記
