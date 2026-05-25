---
phase: 3
name: kaizen-analyze
max_retries: 2
audit: required
---

## Criteria

### K3-01: 4 視点それぞれ最低 1 件
- severity: blocker
- verify_type: automated
- verification: `report.md` の H2 セクション `## Hallucination` / `## User Skill` / `## Config Evolution` / `## Skill Proposals` がそれぞれ最低 1 件の H3（`### H1` 等）を含む
- pass_condition: 全 4 視点で件数 >= 1
- fail_diagnosis_hint: 空の視点があれば「軽微」レベル finding を 1 件追加する。「該当なし」での視点スキップ禁止

### K3-02: 全 finding に transcript 引用
- severity: blocker
- verify_type: automated
- verification: 各 finding ブロック内に `- 引用: "..."` 行が 1 つ以上、引用文字列が空でない
- pass_condition: 引用なし finding が 0 件
- fail_diagnosis_hint: 該当ターンの user / assistant 発話を transcript から直接コピーする。要約・言い換え禁止

### K3-03: 禁止語彙の不使用
- severity: blocker
- verify_type: automated
- verification: report.md 全体で以下のフレーズが出現しない:
  - 「気をつけ」「丁寧に」「明示的に伝え」「明示的に確認」「より注意」
  - 「特に問題なし」「順調」「全体的に良」「次回も気をつけ」
- pass_condition: マッチ 0 件
- fail_diagnosis_hint: 抽象表現を具体的な行動変容に書き換える。「明示的に伝える」→「該当ターンで X を Y 形式で表示する」

### K3-04: User Skill 視点に before/after
- severity: blocker
- verify_type: automated
- verification: User Skill セクションの各 finding に `- Before:` と `- After:` 行のペアが存在
- pass_condition: 全 User Skill finding でペア完備
- fail_diagnosis_hint: ユーザーの実際の発言を Before に、改善案を After に書く

### K3-05: Config Evolution 視点に diff
- severity: blocker
- verify_type: automated
- verification: Config Evolution セクションの各 finding に ` ```diff` フェンスドコードブロックが存在
- pass_condition: diff ブロックなし 0 件
- fail_diagnosis_hint: 適用可能な diff（- / + 行）を書く。「〜を追加する」式の説明文だけは不可

### K3-06: Skill Proposals の分類タグ
- severity: blocker
- verify_type: automated
- verification: Skill Proposals セクションの各 finding に `[A]` / `[B]` / `[C]` のいずれかのタグが付与
- pass_condition: 未分類 0 件
- fail_diagnosis_hint: A（既存使用）/ B（新規推奨）/ C（不要）のいずれかに振り分ける。B の場合は description 草案も必須

### K3-07: 過去再発の検出
- severity: warning
- verify_type: automated
- verification: 全 finding を `~/.kaizen/learning-log.md` の過去エントリと文字列類似度で突合し、類似度 >= 0.7 のものに `⚠ 再発 N 回目` マークが付与されているか
- pass_condition: 再発候補で未マーク 0 件
- fail_diagnosis_hint: learning-log を再 scan し、類似 finding をカウントしてマーク追加

### K3-08: ユーザー側指摘の存在
- severity: blocker
- verify_type: automated
- verification: User Skill セクションの finding 件数 >= 1
- pass_condition: User 側 finding が最低 1 件
- fail_diagnosis_hint: 「ユーザーは悪くない」式の擁護を排除し、曖昧指示・誤前提・指示混在を 1 件以上書き出す
