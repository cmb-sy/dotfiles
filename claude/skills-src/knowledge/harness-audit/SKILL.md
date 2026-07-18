---
name: harness-audit
description: >-
  現在のプロジェクトの開発ハーネス(AIエージェント運用基盤 + テスト/CI基盤)を診断したいときに使う。
  CLAUDE.md・hooks・skills・テスト・CI を5次元の成熟度モデルで実測スコアリングし、
  トップエンジニアの実践(neko-neko/belt 等 + WebSearch の最新ベストプラクティス)をアンカーに
  欠陥・不足・構築手順を教育的に報告、Obsidian vault (02_skillup/harness/) にレポート保存する。
  何もないプロジェクトでは要件定義の確認から入り構築設計書を出す。修正は実行しない(診断・設計・教育に徹する)。
argument-hint: "[--quick] [--focus <A|B|C|D|E>]"
user-invocable: true
---

# Harness Audit — 開発ハーネスの診断・設計・教育

実行したプロジェクトの開発ハーネス全体を、**実在するトップエンジニアの実践**をアンカーにして診断する。未構築なら「どう構築すべきか」の設計から提示する。出力は診断レポートであり、**修正は実行しない**(改善の実行は feature-dev / superpowers フローに委譲。本レポートがその入力になる)。

**開始時アナウンス:** 「Harness Audit を開始します。Phase 1: Inventory」

## 引数

- `--quick`: Phase 2 の Web 調査・ベンチマーク照合を省略(機械チェック+スコアのみ。Level 4 判定は不可)
- `--focus <A-E>`: 指定次元のみ深掘り(他はスコアのみ)

## 評価フレーム: 5次元 × 成熟度 Level 0-4

| 次元 | 見るもの |
|---|---|
| **A. Guardrails** | hooks(破壊的操作・秘密情報・PII 防御)、permissions 設計、サンドボックス方針 |
| **B. Knowledge** | CLAUDE.md の質(ビルド/テスト/lint コマンド・規約・制約・落とし穴)、memory、docs の鮮度と依存追従 |
| **C. Automation** | skills/パイプライン/サブエージェント構成、定型作業の自動化度、context 経済 |
| **D. Verification** | テスト(unit/E2E)・lint・型検査・CI・カバレッジ、done-criteria の機械検証性 |
| **E. Feedback loops** | レビューワークフロー、実行証跡(trace)と計測、振り返り・棚卸しの仕組み |

**Level の定義:**

| Level | 状態 |
|---|---|
| 0 | 不在 |
| 1 | 散文・手動(人間の記憶と注意力に依存) |
| 2 | 部分自動(一部に仕組みがあるが穴が多い) |
| 3 | 体系化(全次元に仕組みがあり、運用に組み込まれている) |
| 4 | トップ実践水準(下記ベンチマークと同等。**照合なしに付けてはならない**) |

## ベンチマーク参照(Level 4 の根拠)

判定・設計提案は次の実在アンカーに照らす。「理想論」を自作しない:

1. **neko-neko/belt** — https://github.com/neko-neko/belt
   パイプラインを YAML 状態機械としてデータ化し `belt lint` で静的検査 / design→plan→build→qa の4ステージ / 役割固定の agent バンドル / エビデンス必須の QA / パイプライン定義を context に載せない context 経済。**C/D 次元の一次参照**
2. **Anthropic 公式の Claude Code ベストプラクティス** — WebSearch で毎回最新を取得(この領域は週次で陳腐化する。学習知識で代用しない)
3. **superpowers 型ワークフロー** — brainstorm→spec→plan→subagent-driven(fresh context/タスク)→二段レビュー→whole-branch レビュー
4. **gain ダイジェスト** — vault の `02_skillup/情報収集/watch/` に直近ダイジェストがあれば読み、ハーネス関連の新機能・新実践を判定材料に加える

## Phase 1: Inventory(実在調査)

**アナウンス:** 「Phase 1: Inventory — ハーネス要素を実測列挙します」

grep/find/ls による**機械列挙**で行う(LLM の推測で「ありそう」と判定しない):

1. スタック検出: 言語・ビルドツール・パッケージマネージャ(lockfile・設定ファイルから)
2. エージェント基盤: `CLAUDE.md`(ルート/配下)、`.claude/`(settings・skills・agents・hooks・commands)、`.mcp.json`、memory 有無
3. 検証基盤: テストディレクトリ・テスト設定、lint/formatter/型検査の設定ファイル、CI 定義(`.github/workflows/` 等)、pre-commit/git hooks
4. ドキュメント: README・docs/ の構成、更新日、コードとの依存関係の宣言有無

出力: 要素ごとの「存在/不在/場所」の一覧表。

### Phase 1.5: 新規構築モードへの分岐（ほぼ何もない場合）

Inventory の結果、全次元が実質 Level 0（エージェント基盤なし・テストなし・CI なし）なら、監査ではなく**要件定義起点の新規構築設計**に切り替える:

1. **要件の確認**: まず既存の要件情報を探す（README・docs/ の仕様書・issue・PRD）。見つかればそれを要件のベースとして読み込む
2. 要件が文書化されていない/不足している場合、AskUserQuestion で最小限を確認する（1問ずつ）:
   - このプロジェクトは何を作るものか（プロダクト種別・ユーザー）
   - スタックの確定度（決定済み/検討中）と品質要件（本番運用か実験か、外部公開か）
   - 開発体制（1人か複数人か、AI エージェント主体か人間主体か）
3. **要件→ハーネス設計の導出**: 確認した要件から逆算して、5次元それぞれの「このプロジェクトに必要な水準」を先に決める（実験リポジトリに Level 4 の CI は過剰。YAGNI）。その水準に向けた構築順序を Phase 4 のロードマップ形式で設計する
4. 以降 Phase 2（ベンチマーク照合は新規設計時必須）→ Phase 4 → Phase 5 を「監査」ではなく「構築設計書」として実行する。スコアカードは現状（ほぼ全て 0）と目標水準の2列で出す

## Phase 2: 並列深掘り + 外部ベンチマーク

**アナウンス:** 「Phase 2: Deep Dive — 並列調査とベンチマーク照合を行います」

`--quick` 時はスキップ。サブエージェント3本を**並列 dispatch**(自己完結プロンプト、構造化データで返させ、生出力を転送しない):

1. **エージェント基盤調査**: CLAUDE.md の内容品質(コマンドが実行可能か・規約が具体か)、hooks の実装読解(fail-open か・ログはあるか)、skills の構成
2. **検証基盤調査**: テストの実行可否(実際に走らせる)、CI の実効性(何を検査しているか)、カバレッジの穴
3. **外部ベンチマーク**: WebSearch で「Claude Code ハーネス/agentic coding ベストプラクティス」の最新を取得 + belt の README/docs を WebFetch(C/D が低そうな場合・新規設計時は必須)。**URL は実在確認したもののみ記録**

オーケストレーターが統合してから Phase 3 へ(理解の再委譲禁止)。

## Phase 3: Assessment(スコアカード)

**アナウンス:** 「Phase 3: Assessment — 5次元スコアを確定します」

- 各次元に Level 0-4 を付け、**必ず evidence(ファイルパス・実行したコマンドと出力)を添える**
- Level 4 はベンチマーク照合の根拠なしに付けない
- 前回レポート(vault `$HOME/develop/obsidian/02_skillup/harness/*-<project>-harness-audit.md` の最新。`<project>` は監査対象リポジトリ名)があれば読み、**次元ごとのスコア推移**を算出する

## Phase 4: Education & Roadmap

**アナウンス:** 「Phase 4: Education — 教育解説とロードマップを構成します」

トップエンジニアが後輩に教えるつもりで書く:

1. **教育解説**: 欠けている要素それぞれに「そもそもそれは何か」「なぜ無いと事故るか」「トップ実践ではどうやっているか(アンカー名を挙げて)」を書く。用語は初出で定義(CLAUDE.md 技術メモと同じ深度)
2. **アーキテクチャ提案**: 未構築/低成熟の場合、このプロジェクトのスタックに合わせた具体構成図(Mermaid or ASCII)と、ファイル配置・命名まで踏み込んだ設計
3. **3段ロードマップ**: 各項目に具体的な手順・コード/設定の雛形を付ける
   - **今すぐ(危険の除去)**: ガード不在・秘密情報露出・テストゼロ等
   - **次(効率化)**: CI 追加・CLAUDE.md 整備・レビューワークフロー等
   - **後で(発展)**: パイプラインのデータ化・trace 計測・自動棚卸し等

## Phase 5: Report

**アナウンス:** 「Phase 5: Report — レポートを保存します」

1. チャットに要約(スコアカード表 + 最重要指摘3点 + 今すぐやること)
2. Obsidian vault `$HOME/develop/obsidian/02_skillup/harness/YYYY-MM-DD-<project>-harness-audit.md` に全文保存:
   - `<project>` は監査対象リポジトリ名(横断蓄積のため必須。ファイル名で対象を区別する)
   - ディレクトリなければ作成、同一プロジェクトを同日に複数回実行する場合は連番
   - `$HOME/develop/obsidian` が存在しない場合は保存せず「vault が見つかりません」と報告して終了する
   - vault への git commit/push はしない(Obsidian の自動 backup に任せる)
   - 中身: frontmatter(date / project / scores / prev_scores) → スコアカード → evidence → 教育解説 → アーキテクチャ → ロードマップ → 参照 URL
3. 前回レポート(同一 `<project>`)がある場合、冒頭にスコア推移表(前回→今回)を必ず載せる

## Red Flags(やってはいけないこと)

- evidence なしでスコアを付ける(「ありそう」判定の禁止)
- ベンチマーク照合なしに Level 4 を付ける / 逆に理想論を自作して 0-3 を辛口にする
- 修正を実行する(診断・設計・教育に徹する。実行は feature-dev / superpowers フローへ)
- 教育解説を省いて指摘の列挙だけにする(教育がこのスキルの存在意義)
- WebSearch を省略して学習知識だけで「最新のベストプラクティス」を語る(`--quick` 時は Level 4 判定と最新実践の主張自体を控える)
- サブエージェントの生出力を統合せずレポートへ転送する

## 他スキルとの棲み分け

- **doc-audit**: ドキュメントの陳腐化検査(md が対象)。本スキルは開発基盤全体が対象で、docs は B 次元の一部
- **skills-audit**: スキルの利用実績・重複の棚卸し(dotfiles 運用)。本スキルはプロジェクト単位のハーネス診断
- **code-review**: 変更差分の品質。本スキルは差分ではなく基盤の構造
