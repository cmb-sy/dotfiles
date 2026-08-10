---
name: pipeline-gates
description: >-
  パイプライン系スキル（feature-dev / debug-flow）共通のゲート仕様。起動時の Resume Gate
  （中断した実行の再開判定）と、フェーズ遷移の絶対条件である Mandatory Audit Gate を定義する。
---

# Pipeline Gates

## 呼び出し元スキルが定義するもの

| 項目 | 内容 |
|------|------|
| pipeline 識別子 | `project-state.json` の `pipeline` と照合するスキル名 |
| 復元するフラグ | Resume Mode で `args` から復元するフラグの一覧（各スキルの Options） |
| done-criteria | フェーズごとの基準ファイルのパス（既定: `./done-criteria/phase-N-{name}.md`） |

## Resume Gate（最優先で評価）

起動時に以下を確認:
1. `.agents/handover/` 配下に現在ブランチの READY セッションが存在するか
2. 複数 READY セッションがある場合、タイムスタンプ（fingerprint）が最新のものを選択
3. 存在する場合、`project-state.json` の `pipeline` が呼び出し元の pipeline 識別子と一致するか

一致する場合 → **Resume Mode** で起動する（Phase 1 からの通常フローをスキップ）。
一致しない場合 → 通常の新規起動。

### Resume Mode 実行フロー

1. `project-state.json` を読み込む
2. `args` から呼び出し元が宣言したフラグを復元する
3. `phase_observations[]` + `session_notes[]` から soft context を表示する:
   - `relates_to_phase` が `current_phase` 以降 → 全件表示
   - `relates_to_phase` が `current_phase` より前 → `directive` / `concern` のみ
   - 表示順: directive → concern → insight → quality → warning
4. 再開位置を表示し、ユーザー承認を得る:
   ```
   Pipeline: {pipeline 識別子} ({復元されたフラグ})
   現在: Phase {N} {name}（{status}）

   [前セッションからの引き継ぎ]
   - ⚠ {session_notes / phase_observations の要約}

   [監査状態]
   - Phase {N} Audit: {状態} / attempt {M} of {max_retries}

   この状態から再開します。よろしいですか？
   ```
5. 承認後、`current_phase` のフェーズから作業を続行する
6. 以降は通常のフェーズ遷移ルール・監査ゲートに従う

### フェーズ途中 vs フェーズ間の再開

- **フェーズ途中**（`active_tasks` に `in_progress` あり）: 残タスクから再開。完了時に done-criteria で監査
- **フェーズ間**（前フェーズ完了、次フェーズ未開始）: 前フェーズの監査ゲートが PASS 済みか確認。未実施なら監査から実行

### Resume Mode で「やらないこと」

- Phase 1 からのやり直し（`completed_phases` はスキップ）
- 完了済みフェーズの再監査（コミット SHA が git log に存在すれば信頼）
- 新規起動時の引数パース（`args` は `project-state.json` から復元）

<HARD-GATE>
## Mandatory Audit Gate — フェーズ遷移の絶対条件

フェーズ遷移は Audit Gate を経由しなければならない。例外なし。

各フェーズの作業完了後、次フェーズへ遷移する前に:
1. `./done-criteria/phase-N-{name}.md` を Read で読み込む
2. frontmatter の `audit` フィールドを確認する
3. `audit: required` → phase-auditor を Agent ツールで起動し、PASS verdict を得る
4. `audit: lite` → オーケストレーターが done-criteria の基準を直接検証する
5. `audit` 未定義 → `required` として扱う

以下はスキップの理由にならない:
- 「前のフェーズで十分に検証した」
- 「シンプルな変更だから不要」
- 「レビュースキルが既に品質を確認した」
- 「時間/トークンを節約したい」

phase-auditor の verdict なしに Phase N+1 のアナウンスや作業開始を行った場合、
それは**プロトコル違反**である。
</HARD-GATE>
