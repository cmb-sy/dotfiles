---
phase: 8
name: visual-audit
max_retries: 3
audit: required
---

## Criteria

### P8-01: フォントサイズ下限
- severity: blocker
- verify_type: automated
- verification: `audit_visual.py` の出力 `font_violations` 配列を確認
- pass_condition: font_violations の要素数が 0（本文 14pt 未満・タイトル 24pt 未満の text frame が 0 件）
- fail_diagnosis_hint: `tokens.yaml` の font_size_body / font_size_title を引き上げる、または該当スライドのテキスト量を減らす
- depends_on_artifacts: [.pptx-dev/<session-id>/visual-audit.json]

### P8-02: コントラスト比
- severity: blocker
- verify_type: automated
- verification: `contrast_violations` 配列を確認
- pass_condition: contrast_violations の要素数が 0（WCAG AA = 4.5:1 を下回る text frame が 0 件）
- fail_diagnosis_hint: `tokens.yaml` の accent_color / text_color を調整するか、テンプレを変更
- depends_on_artifacts: [.pptx-dev/<session-id>/visual-audit.json]

### P8-03: テキストオーバーフロー
- severity: blocker
- verify_type: automated
- verification: `overflow_violations` 配列を確認
- pass_condition: overflow_violations の要素数が 0
- fail_diagnosis_hint: 該当スライドの文字数削減または layout 変更（two_column → 2 枚に分割など）
- depends_on_artifacts: [.pptx-dev/<session-id>/visual-audit.json]

### P8-04: 整列ズレ
- severity: warning
- verify_type: automated
- verification: `alignment_violations` 配列を確認
- pass_condition: alignment_violations の要素数 ≤ 3（同種要素が ±2pt を超えてずれているケース）
- fail_diagnosis_hint: generate.py のレイアウト計算ロジックを見直す
- depends_on_artifacts: [.pptx-dev/<session-id>/visual-audit.json]

### P8-05: 余白
- severity: warning
- verify_type: automated
- verification: `margin_violations` 配列を確認
- pass_condition: margin_violations の要素数 ≤ 3（スライド端から本文まで 24pt 未満）
- fail_diagnosis_hint: tokens.yaml の margin を引き上げる
- depends_on_artifacts: [.pptx-dev/<session-id>/visual-audit.json]

### P8-06: 空スライド
- severity: blocker
- verify_type: automated
- verification: `empty_slides` 配列を確認
- pass_condition: empty_slides の要素数が 0（タイトルのみで本文空のスライド。section layout 除く）
- fail_diagnosis_hint: 該当スライドに content を追加するか layout を section に変更
- depends_on_artifacts: [.pptx-dev/<session-id>/visual-audit.json]
