---
name: skills-map
argument-hint: "[--category <カテゴリ名>] [--deps] [--search <キーワード>]"
---

保持しているスキルをカテゴリー別・依存関係付きで一覧表示する。

**モード:**
- **引数なし**: 全スキルをカテゴリー別に表示（説明・使い方付き）
- **`--category <名前>`**: 指定カテゴリのスキルのみ詳細表示
- **`--deps`**: スキル間の依存関係図のみ表示
- **`--search <キーワード>`**: キーワードに部分一致するスキルを横断検索

---

## 処理フロー

### Step 1: スキルの収集

以下のディレクトリを並列で走査し、全 SKILL.md を収集する。

- `~/.claude/skills/` （グローバル dotfiles スキル）
- `{current_project}/.claude/skills/` （プロジェクト固有スキル。存在すれば）

各 SKILL.md から以下を抽出する:
- frontmatter の `name` と `argument-hint`
- 1行目の説明文（frontmatter 直後の最初の非空行）
- 本文中の `--` フラグの列挙
- 他スキルへの invoke 言及（依存関係の抽出）

### Step 2: カテゴリー分類

抽出したスキルを以下のカテゴリーに分類する。

| カテゴリー | 対象スキル |
|---|---|
| 開発フロー | feature-dev, debug-flow, tdd-orchestrate, smoke-test |
| コードレビュー | code-review, test-review, implementation-review, spec-review |
| ドキュメント | doc-audit, doc-check, learn, handover, continue |
| プロジェクト管理 | linear-refresh, github-ops, triage, project-update |
| 振り返り・成長 | reflect, reflect-review |
| 外部ツール連携 | slackcli, trace-report |
| Obsidian 固有 | daily-log, eod（プロジェクト設定スキル） |

プロジェクト固有スキル（.claude/skills/）は「Obsidian 固有」または「プロジェクト固有」として別枠に表示する。

### Step 3: 出力

**引数なしの場合 — 全スキルカテゴリー別一覧:**

```
=============================================
  Claude Skills Map  (グローバル N 件 + プロジェクト M 件)
=============================================

[開発フロー]

  feature-dev          [--codex] [--e2e] [--smoke]
    10フェーズの品質ゲート付き開発オーケストレーター。
    設計→レビュー→計画→実装→監査→テスト→統合を一気通貫で実行。
    呼び出し: spec-review, implementation-review, code-review,
              test-review, smoke-test, doc-audit, doc-check, learn

  debug-flow           [--codex]
    8フェーズの品質ゲート付きデバッグオーケストレーター。
    根本原因分析→修正計画→レビュー→実装→スモークテスト→統合。
    呼び出し: code-review, test-review, smoke-test

  tdd-orchestrate
    TDDスタイルの機能実装オーケストレーター。
    設計→計画→TDD実装→統合を1セッションで完結。
    呼び出し: spec-review, implementation-review, code-review, test-review

  smoke-test
    ローカルスモークテスト。dev起動→テスト生成→VRT差分→E2E実行。

[コードレビュー]

  code-review          [--codex] [--iterations N]
    7観点（品質/セキュリティ/性能/テスト/AIアンチパターン等）の並列レビュー。

  test-review          [--design] [--codex] [--iterations N]
    3観点（カバレッジ/品質/設計整合）のテストコードレビュー。

  implementation-review [--codex] [--iterations N]
    3観点（明確性/実現可能性/整合性）の実装計画書レビュー。

  spec-review          [--codex] [--iterations N]
    4観点（要件/設計判断/実現可能性/整合性）の設計書レビュー。

[ドキュメント]

  doc-audit
    4Layer構造でドキュメントの陳腐化・欠落・矛盾を検出。

  doc-check
    コード変更に影響を受けるmdドキュメントを検出・更新。

  learn
    実装完了後に自動で学習教材を生成（docs/learnings/へ出力）。

  handover
    現在のセッション内容を振り返り、次セッション向けに要約を出力。

  continue
    handover.md から未完了タスクを読み込み作業を再開。
    呼び出し: handover（連携）

[プロジェクト管理]

  linear-refresh       [--force] [--skip-discovery] [--cleanup-only] [--add-only]
                       [--project-update] [--daily-log]
    Linearチケット棚卸し・構造整理・新規検出を一気通貫で実行。
    呼び出し: slackcli, project-update, daily-log（オプション）

  github-ops
    PR作成とGitHub Projects登録を一気通貫で実行。

  triage
    URL/Slack/GitHubから情報収集→分析→Linear Issue登録の初動対応。

  project-update
    議事録・Slack・GitHubを統合してプロジェクトファイルを更新。
    呼び出し: slackcli

[振り返り・成長]

  reflect              [YYYY-MM-DD | "説明テキスト"] [--quick]
    作業を問題形式で振り返り、理解ギャップを可視化。
    結果を daily ノートと 01_quant/reflect_log.md に記録。

  reflect-review       [--weekly | --monthly]
    reflect_log の累積データを分析し成長を言語化。
    正答率が低い問題を再出題して定着確認。
    呼び出し: reflect_log.md（依存）

[外部ツール連携]

  slackcli
    Slack CLI ラッパー。メッセージ送受信・チャンネル検索・スレッド取得。

  trace-report
    trace.jsonl を分析し、パイプラインの振り返りレポートを生成。

[Obsidian 固有（プロジェクト設定）]

  daily-log            [YYYY-MM-DD] [--session] [--cloudlog] [--linear-refresh]
                       [--exclude <キーワード>...]
    既存の日報ファイルに今日やったことを自動集約。
    --cloudlog で勤怠システムへの Playwright 自動入力も実行。
    呼び出し: slackcli, linear-refresh（オプション）

  eod                  [--exclude <キーワード>...]
    1コマンドで作業を締める。linear-refresh→daily-log→project-update→CloudLog入力。
    呼び出し: linear-refresh, daily-log, project-update

=============================================
  依存関係の概要 (/skills-map --deps で詳細)
=============================================

  feature-dev ──> spec-review, implementation-review, code-review,
                  test-review, smoke-test, doc-audit, doc-check, learn
  debug-flow ───> code-review, test-review, smoke-test
  eod ──────────> linear-refresh ──> slackcli, project-update
  eod ──────────> daily-log ──────> slackcli
  reflect-review -> reflect_log (file)
  handover <──── continue
```

**`--deps` の場合 — 依存関係図のみ:**

```
依存関係図（A --> B は「A が B を呼び出す」）

開発フロー
  feature-dev ──┬──> spec-review
                ├──> implementation-review
                ├──> code-review ──> (並列サブエージェント)
                ├──> test-review ──> (並列サブエージェント)
                ├──> smoke-test
                ├──> doc-audit
                ├──> doc-check
                └──> learn

  debug-flow ───┬──> code-review
                ├──> test-review
                └──> smoke-test

  tdd-orchestrate ─┬──> spec-review
                   ├──> implementation-review
                   ├──> code-review
                   └──> test-review

Obsidian 日次ワークフロー
  eod ──────────┬──> linear-refresh ──┬──> slackcli
                │                     └──> project-update ──> slackcli
                ├──> daily-log ────────┬──> slackcli
                │                     └──> (linear-refresh の結果を再利用)
                └──> project-update

セッション継続
  handover ←──────── continue (handover.md を読む)

振り返り
  reflect ──────────> 01_quant/reflect_log.md
  reflect-review ───> 01_quant/reflect_log.md (読み取り)
```

**`--category <名前>` の場合 — 指定カテゴリを詳細表示:**

対象カテゴリのスキルのみ、上記の詳細フォーマットで表示する。
カテゴリ名は部分一致で解釈する（例: `--category レビュー` → コードレビューを表示）。

**`--search <キーワード>` の場合 — キーワード横断検索:**

全スキルの説明・フラグ・依存関係からキーワードに一致するスキルを返す。

```
"linear" で検索:
  linear-refresh  — Linearチケット棚卸し（直接一致）
  triage         — Linear Issue 登録を含む
  eod            — linear-refresh を呼び出す
  daily-log      — --linear-refresh フラグを持つ
```

---

## ルール

1. 出力はプレーンテキストのみ。特殊文字・絵文字・装飾記号は使わない
2. スキルファイルを実際に Read して内容を確認する（ハードコードした内容を返すだけにしない）
3. プロジェクト固有スキル（.claude/skills/）が存在すれば自動検出してグローバルと区別して表示する
4. 依存関係は SKILL.md 本文中の「invoke」「呼び出し」「スキル名への言及」から動的に抽出する
5. 新しいスキルが追加されても自動的に反映される（ハードコードリストではなくディレクトリ走査）
