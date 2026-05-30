---
phase: 4
name: stock-analyze
max_retries: 2
audit: required
---

## Criteria

### S4-01: 全ティッカーで Composite Score 確定
- severity: blocker
- verify_type: automated
- verification: `analysis.json` の各ティッカーに `composite_score` フィールドが数値 (0-100) または文字列 `"N/A"` で存在
- pass_condition: 欠落 0 件
- fail_diagnosis_hint: 取得経路（yfinance / WebFetch）の選択を見直す、または該当ティッカーを除外

### S4-02: 各サブスコアの定義域
- severity: blocker
- verify_type: automated
- verification:
  - technical_score ∈ [0, 50] または `"N/A"`
  - fundamental_score ∈ [0, 50] または `"N/A"`
  - sentiment_score ∈ [0, 100] または `"N/A"`
- pass_condition: 範囲外 0 件
- fail_diagnosis_hint: analyze.py のスコアリングロジックを修正

### S4-03: Recommendation の値域
- severity: blocker
- verify_type: automated
- verification: 各ティッカーの `recommendation` フィールドが `Buy` / `Hold` / `Sell` / `Wait` のいずれか
- pass_condition: 不正値 0 件
- fail_diagnosis_hint: LLM プロンプトの出力形式制約を見直す。フリーフォーマットでなく enum 限定で出力させる

### S4-04: Recommendation の根拠
- severity: blocker
- verify_type: manual
- verification: 各ティッカーの `recommendation_reason` フィールドが 1 文以上の自然言語で存在
- pass_condition: 空文字 0 件
- fail_diagnosis_hint: LLM プロンプトに「100 字以内の根拠を必須」と明示

### S4-05: N/A 比率の警告
- severity: warning
- verify_type: automated
- verification: 全サブスコア × 全ティッカーのうち N/A の比率
- pass_condition: N/A 比率 < 50%
- fail_diagnosis_hint: データソース不調の可能性。Claude Code path なら yfinance 再試行、Desktop path なら WebFetch のリトライ間隔を空ける

### S4-06: Composite Score の再現性
- severity: blocker
- verify_type: manual
- verification: 同じ raw データで analyze.py を再実行し、composite_score が ±0.1 以内で一致
- pass_condition: 再現性 OK
- fail_diagnosis_hint: ランダム要素（時刻依存、乱数）が混入していないか確認。重み定数 0.3 / 0.4 / 0.3 から逸脱していないか確認

### S4-07: Notion mode 限定: 保有データ参照
- severity: blocker（Notion mode 時のみ適用）
- verify_type: manual
- verification: Notion mode かつ Status = `Holding` の銘柄について、`recommendation_reason` に P&L または Target/Stop との比較言及があること。さらに、当該銘柄に直近 30 日の材料が存在する場合は、その材料（日付付き）への言及があること
- pass_condition: 該当銘柄全てで保有コンテキストが反映されており、材料がある銘柄はその言及もある
- fail_diagnosis_hint: LLM プロンプトに保有データと材料ブロックを明示的に渡す。Notion mode のシステムプロンプトに「保有状況と材料を必ず判断材料に含める」と追記

### S4-08: 材料の出典・新鮮度
- severity: blocker
- verify_type: automated
- verification: `material.json` に採用された各材料エントリが以下を満たす
  - `url` フィールドが非空の有効な URL 文字列
  - `published_date` が `YYYY-MM-DD` 形式で、実行日から 30 日以内（実行日 − 30 日 ≤ published_date ≤ 実行日）
  - `category` が `earnings` / `guidance` / `capital` / `ma` / `rating` / `order` / `regulatory` のいずれか
- pass_condition: 条件違反のエントリ 0 件（違反エントリは採用前に破棄されているべき）
- fail_diagnosis_hint: Phase 3b の採用条件フィルタを見直す。URL/日付欠落・30 日超・不正 category を採用前に除外する。材料 0 件は空配列 `[]` で正常（違反ではない）
