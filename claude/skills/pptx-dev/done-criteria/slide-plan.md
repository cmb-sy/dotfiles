---
phase: 5
name: slide-plan-review
max_retries: 2
audit: required
---

## Criteria

### P5-01: ストーリー根拠の全カバー
- severity: blocker
- verify_type: manual
- verification: `storyline.md` の根拠 bullets と `slide-plan.yaml` の slides を突き合わせ、根拠ごとに最低 1 枚スライドが対応していること
- pass_condition: 全根拠が 1 枚以上の slide に紐付く
- fail_diagnosis_hint: 未対応の根拠用にスライドを追加するか、根拠を削除する

### P5-02: スライド枚数と所要時間の整合
- severity: blocker
- verify_type: automated
- verification: `len(slides) <= brief.target_slides * 1.2`
- pass_condition: 想定枚数の 120% 以内
- fail_diagnosis_hint: 枚数を削減するか、所要時間を見直す

### P5-03: layout の妥当性
- severity: blocker
- verify_type: automated
- verification: 各 slide の `layout` フィールドが `title / section / content / two_column / chart / quote / closing` のいずれか
- pass_condition: 不正な layout が 0 件
- fail_diagnosis_hint: 規定の layout 名に修正

### P5-04: 1 スライド 1 メッセージ
- severity: warning
- verify_type: manual
- verification: 各 `content` layout のスライドで bullets 数が 5 以内、要点が複数主張にまたがっていないこと
- pass_condition: bullets ≤ 5 かつ 1 主張
- fail_diagnosis_hint: スライド分割または bullets の絞り込み

### P5-05: 出典の明示（data・引用のあるスライド）
- severity: warning
- verify_type: manual
- verification: `chart` layout または引用を含む slide に `chart.data_source` または notes に出典が記載されていること
- pass_condition: 該当 slide で出典記述あり
- fail_diagnosis_hint: notes に出典を追記

### P5-06: pacing
- severity: warning
- verify_type: manual
- verification: 5 枚ごとに 1 枚以上の `section` または `chart` スライド（視覚的休憩点）が含まれること
- pass_condition: 5 枚連続で `content` が続くブロックが存在しない
- fail_diagnosis_hint: section / chart layout を挿入

### P5-07: レビュー findings の反映
- severity: blocker
- verify_type: manual
- verification: `slide-plan-review.md` の approved findings 全件が `slide-plan.yaml` に反映済みか
- pass_condition: 未反映 0 件
- fail_diagnosis_hint: 未反映の指摘を反映するか、却下理由を追記
