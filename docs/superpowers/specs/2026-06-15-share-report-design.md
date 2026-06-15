---
title: /share-report — 業務サイド向けセッション報告書 HTML 生成 skill
status: approved
created: 2026-06-15
updated: 2026-06-15
owner: snakashima
---

# /share-report 設計書

## 目的・スコープ

セッション内で実施した依頼の結果を、業務部門ステークホルダーに Slack/Teams 添付で共有できる単一 HTML レポートにまとめる skill を新設する。

- 読み手は非エンジニア（PM・営業・運用担当などの業務部門ステークホルダー）。
- コード・コマンド・ファイルパス等の技術詳細は完全に除外し、業務語彙のみで構成する。
- 報告者は画面共有しながら受け取ったコメントをその場で書き込めるメモ欄を持つ。
- 共有手段は Slack/Teams 添付前提のため、単一 HTML ファイルで自己完結させる（外部依存ゼロ）。
- 編集後のアウトプットは HTML / PDF の両形式で書き出せる。

## 想定ユーザー・読み手

| 役割     | 想定                                                                  |
| -------- | --------------------------------------------------------------------- |
| 報告者   | snakashima（DXP/AITF プロジェクトでの作業を業務サイドに共有する）     |
| 読み手   | 業務部門ステークホルダー（PM/営業/運用担当）。技術的予備知識を持たない |
| 受け渡し | Slack/Teams に HTML/PDF ファイルを添付。読み手はローカルで開く        |

## アーキテクチャ

```
┌─────────────────────────────────────────────────────┐
│  /share-report  (user invokes)                      │
└─────────────────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────┐
│ Step 1: セッション内容抽出 (LLM 推論)               │
│  - サマリー (依頼内容・背景)                         │
│  - やったこと                                        │
│  - 残課題・次のアクション                            │
│  - 確認事項                                          │
│  - 業務語彙へ翻訳 / 技術詳細を完全に除外            │
│  - --dry-run 時は本 Step 完了後にチャット表示で終了 │
└─────────────────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────┐
│ Step 2: HTML テンプレートに差し込み                 │
│  - 単一HTML完結 (CSS/JSインライン、外部依存なし)    │
│  - contenteditable 編集UI                           │
│  - 打ち合わせメモ欄 (空欄でスタート)                │
│  - 3 つのツールバーボタン                            │
│      編集モード ON/OFF                              │
│      PDF として保存 (window.print())                │
│      HTML として保存 (Blob ダウンロード)            │
└─────────────────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────┐
│ Step 3: 保存 + プレビュー                           │
│  - ~/Documents/reports/session-report-YYYY-MM-DD-HHMM.html │
│  - macOS `open` でブラウザ表示                       │
└─────────────────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────┐
│ Step 4: ユーザーがブラウザで編集 → 書き出し         │
│  - contenteditable で本文・メモ編集                 │
│  - 「PDF として保存」: 印刷ダイアログ → PDF        │
│  - 「HTML として保存」: 編集UI除去版を              │
│    `*-edited-YYYYMMDD-HHMMSS.html` でダウンロード   │
└─────────────────────────────────────────────────────┘
```

## HTML 構造

```html
<header>
  <h1>{{TITLE}}</h1>
  <div class="meta">{{DATE}}</div>
</header>

<section id="summary">
  <h2>1. サマリー</h2>
  <div contenteditable="true">{{SUMMARY_BODY}}</div>
</section>

<section id="activities">
  <h2>2. やったこと</h2>
  <ul contenteditable="true">{{ACTIVITIES_ITEMS}}</ul>
</section>

<section id="next-actions">
  <h2>3. 残課題・次のアクション</h2>
  <ul contenteditable="true">{{NEXT_ACTIONS_ITEMS}}</ul>
</section>

<section id="confirmations">
  <h2>4. 確認事項</h2>
  <ul contenteditable="true">{{CONFIRMATIONS_ITEMS}}</ul>
</section>

<section id="meeting-notes">
  <h2>5. 打ち合わせメモ</h2>
  <div contenteditable="true" data-placeholder="ここに打ち合わせ中のメモを書き込めます"></div>
</section>

<aside id="toolbar">
  <button id="toggle-edit">編集モード: ON</button>
  <button id="export-pdf">PDF として保存</button>
  <button id="save-html" class="primary">HTML として保存</button>
</aside>
```

## 変数プレースホルダ

| 変数                       | 内容                                                                  |
| -------------------------- | --------------------------------------------------------------------- |
| `{{TITLE}}`                | レポートタイトル（`<title>` と `<h1>` の 2 箇所に同じ値を置換）       |
| `{{DATE}}`                 | 今日の日付（YYYY-MM-DD）                                              |
| `{{SUMMARY_BODY}}`         | サマリー本文。`<p>...</p>` の連続                                     |
| `{{ACTIVITIES_ITEMS}}`     | やったこと一覧。`<li>...</li>` の連続                                 |
| `{{NEXT_ACTIONS_ITEMS}}`   | 残課題・次のアクション一覧。`<li>...</li>` の連続                     |
| `{{CONFIRMATIONS_ITEMS}}`  | 確認事項一覧。`<li>...</li>` の連続                                   |

## スタイル方針

- ベースカラー: ティール `#139cab` (`--brand`) / 濃ティール `#0f7d89` (`--brand-dark`) / 薄ティール `#e8f6f8` (`--brand-soft`)
- 本文系: 黒 `#1a1a1a` (`--ink`) / 中グレー `#555` / 薄グレー `#888` / 罫線 `#d8d8d8` / 背景アクセント `#f5f5f5`
- 見出し: h1=26px / h2=18px、font-weight 700、color `--brand-dark`
- ヘッダー下線は 2px solid `--brand`
- body max-width: 1024px
- フォント: `-apple-system, BlinkMacSystemFont, "Segoe UI", "Hiragino Sans", "Noto Sans JP", sans-serif`
- contenteditable 領域: ホバーで点線枠、focus で `--brand` 色枠
- 打ち合わせメモ (`#meeting-notes`): 薄グレー `--bg-soft` 背景（黄色付箋風は不採用、シンプル路線）
- 印刷向け media query: ツールバー非表示、編集枠線・placeholder 抑止、メモ欄背景透明、`page-break-inside: avoid`
- 全 CSS をインライン化、画像は使用しない
- 絵文字・アイコンは使わない（業務文書らしさ優先）

## ボタンの挙動

### 編集モード ON/OFF (`#toggle-edit`)
- クリックで `editing` フラグを反転
- 全 `[contenteditable]` 要素の属性を `String(editing)` に書き換え
- `body.preview` クラスのトグル（編集枠線を CSS 側で消す）
- ボタンテキスト「編集モード: ON」⇔「編集モード: OFF」

### PDF として保存 (`#export-pdf`)
- `window.print()` を呼ぶのみ
- ブラウザの印刷ダイアログから「PDF として保存」を選んで PDF 出力
- `@media print` ルールで編集 UI が自動で隠れる

### HTML として保存 (`#save-html.primary`)
```text
1. document.documentElement.cloneNode(true) で複製
2. クローン側で:
   - <aside id="toolbar"> を削除
   - 全要素から contenteditable 属性を削除
   - data-placeholder 属性を削除
   - 編集用 <script> を全て削除
3. <!DOCTYPE html>\n + outerHTML を Blob (type="text/html;charset=utf-8") 化
4. <a download="{元ファイル名}-edited-YYYYMMDD-HHMMSS.html"> を生成 → click() 起動
5. 元ファイルは触らない (上書きしない)
6. URL.revokeObjectURL を 1000ms 遅延で実行 (Safari ダウンロード保護)
```

## 呼び出し方・引数

```
/share-report                            # デフォルト動作
/share-report --title "X 機能改善報告"   # タイトル上書き
/share-report --to /path/file.html       # 出力先上書き
/share-report --no-open                  # 自動プレビュー無効化
/share-report --dry-run                  # 生成せずチャットにドラフト Markdown のみ提示
```

## 処理ルール

1. **業務語彙のみ**: ファイルパス、コマンド、コード断片、ライブラリ名、フラグ、GitHub/Linear ID 等の技術アーティファクトを一切出さない。「Slack の Bot トークンを env に追加」→「Slack 連携の設定情報を整備」のように翻訳する。
2. **やったことは具体的に**: 「色々やった」「整備した」では弱い。読み手の業務がどう変わるかが伝わる粒度で書く。
3. **確認事項は問いの形で**: 「これで良いか」「どちらに統一するか」「いつから運用するか」など、依頼者が判断・回答できる質問形式にする。
4. **メモ欄は空でスタート**: AI が予想で埋めない。
5. **PII 除外**: セッション中の個人情報（氏名・連絡先等）は出力に含めない。CLAUDE.md「PII Protection」セクションのマスキング規則（例: `田中***`, `090-****-****`）に従う。
6. **空セッション保護**: 報告内容を抽出できない（純粋に雑談・調査のみで成果物がないセッション等）の場合は HTML を生成せず「報告対象の作業が見当たりません」と通知して終了。
7. **再生成では上書きしない**: タイムスタンプ付きファイル名で別ファイルとして保存。
8. **ユーザー発言の逐語転記禁止**: プロンプトインジェクションと機密漏洩を抑止するため、ユーザー指示文・コードブロック・チャット原文をそのままコピーしない。

## ファイル配置

- skill 本体: `/Users/snakashima/dotfiles/claude/skills-src/ops/share-report/SKILL.md`
- HTML テンプレート: `/Users/snakashima/dotfiles/claude/skills-src/ops/share-report/template.html`
- symlink: `/Users/snakashima/dotfiles/claude/skills/share-report → ../skills-src/ops/share-report`
- 出力先: `~/Documents/reports/session-report-YYYY-MM-DD-HHMM.html`
- カテゴリは `ops`（english-log / handover / eod など報告系と同列）

## エラーハンドリング

| ケース                                       | 挙動                                                                       |
| -------------------------------------------- | -------------------------------------------------------------------------- |
| 報告対象の作業がない                         | HTML を生成せず通知のみ「報告対象の作業が見当たりません」                  |
| `~/Documents/reports/` が無い                | 自動作成                                                                   |
| `--to` で指定したディレクトリ親が存在しない  | エラー表示で中止（自動作成しない、誤指定保護）                             |
| `open` コマンドが失敗                        | 警告のみ。ファイル保存は成功扱い                                           |
| 既に同名ファイルが存在                       | ファイル名末尾に `-2`, `-3` ... を付与して衝突回避                         |
| template.html が見つからない                 | エラー: skill のセットアップが壊れている旨を伝え、dotfiles の再 clone / symlink 修復を案内 |

## テスト方針

skill は宣言的ロジックが中心のため、検証は以下の手動チェックで行う：

1. **happy path**: 1セッション分の作業後に `/share-report` を実行 → ファイル生成 → ブラウザ表示 → 編集 → HTML/PDF 書き出しが意図通り
2. **空セッション**: 起動直後に何もせず `/share-report` → 「報告対象の作業が見当たりません」が出ること
3. **業務語彙チェック**: 出力 HTML 内に `.py`, `.ts`, `git`, `npm`, `linear`, ファイルパス、GitHub/Linear ID 等のキーワードが含まれないこと
4. **PII チェック**: テストとして個人名を含むセッションを行い、出力に氏名がマスキングされていること
5. **オフライン動作**: 生成 HTML をオフライン環境で開いて全機能（編集 / HTML 保存 / PDF 印刷ダイアログ）が動作すること
6. **印刷プレビュー**: ブラウザの印刷プレビューでツールバー・編集枠線が非表示、メモ欄背景が白になっていること
7. **再実行**: 同じセッション内で2回連続実行しても上書きされず別ファイルが作られること
8. **引数**: `--title`, `--to`, `--no-open`, `--dry-run` の各引数が想定通り作用すること

## スコープ外（YAGNI）

- 複数テンプレ切替（社外用/社内用など）
- 既存レポートへの追記マージ
- Slack/Teams への自動アップロード
- メモ欄の Markdown レンダリング
- 編集履歴の version 管理
- レポート間のリンク・参照
- 多言語対応（日本語固定）
- クライアントサイド PDF ライブラリ埋込（jsPDF 等。ファイル肥大化のため不採用、印刷ダイアログ経由で代替）

## 関連 skill

- `handover`: セッション全体（技術詳細含む）を Claude 自身が引き継ぐためのファイル。技術者向け。
- `learn`: 技術学習材料を `docs/learnings/` に永続化。技術者向け。
- `english-log`: 英語学習材料を Obsidian に蓄積。学習者向け。
- `eod`: 1日の作業の締め処理。デイリーログ等。

`share-report` は上記いずれとも異なる「非エンジニア向け業務報告」専用の出力先を持つ。
