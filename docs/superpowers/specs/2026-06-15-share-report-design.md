---
title: /share-report — 業務サイド向けセッション報告書 HTML 生成 skill
status: approved
created: 2026-06-15
owner: snakashima
---

# /share-report 設計書

## 目的・スコープ

セッション内で実施した依頼の結果を、業務部門ステークホルダーに Slack/Teams 添付で共有できる単一 HTML レポートにまとめる skill を新設する。

- 読み手は非エンジニア（PM・営業・運用担当などの業務部門ステークホルダー）。
- コード・コマンド・ファイルパス等の技術詳細は完全に除外し、業務語彙のみで構成する。
- 報告者は画面共有しながら受け取ったコメントをその場で書き込めるメモ欄を持つ。
- 共有手段は Slack/Teams 添付前提のため、単一 HTML ファイルで自己完結させる（外部依存ゼロ）。

## 想定ユーザー・読み手

| 役割     | 想定                                                                  |
| -------- | --------------------------------------------------------------------- |
| 報告者   | snakashima（DXP/AITF プロジェクトでの作業を業務サイドに共有する）     |
| 読み手   | 業務部門ステークホルダー（PM/営業/運用担当）。技術的予備知識を持たない |
| 受け渡し | Slack/Teams に HTML ファイルを添付。読み手はローカルでブラウザで開く  |

## アーキテクチャ

```
┌─────────────────────────────────────────────────────┐
│  /share-report  (user invokes)                      │
└─────────────────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────┐
│ Step 1: セッション内容抽出 (LLM 推論)               │
│  - 依頼サマリ・背景                                  │
│  - Before / After (実現したこと)                    │
│  - 残課題・次のアクション                            │
│  - 業務語彙へ翻訳 / 技術詳細を完全に除外            │
└─────────────────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────┐
│ Step 2: HTML テンプレートに差し込み                 │
│  - 単一HTML完結 (CSS/JSインライン、外部依存なし)    │
│  - contenteditable 編集UI                           │
│  - 打ち合わせメモ欄                                  │
│  - 「保存」ボタン (Blob ダウンロード)               │
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
│ Step 4: ユーザーがブラウザで編集 → 保存             │
│  - contenteditable で本文・メモ編集                 │
│  - 「保存」ボタンで編集UI/操作バー除去版を          │
│    `*-edited.html` としてダウンロード               │
└─────────────────────────────────────────────────────┘
```

## HTML 構造

```html
<header>
  <h1>{TITLE}</h1>
  <div class="meta">{YYYY-MM-DD}</div>
</header>

<section id="summary">
  <h2>1. ご依頼のサマリと背景</h2>
  <div contenteditable="true">{SUMMARY_BODY}</div>
</section>

<section id="before-after">
  <h2>2. 実現したこと</h2>
  <table>
    <thead><tr><th>変更前 (Before)</th><th>変更後 (After)</th></tr></thead>
    <tbody contenteditable="true">{BEFORE_AFTER_ROWS}</tbody>
  </table>
</section>

<section id="next-actions">
  <h2>3. 残課題・次のアクション・確認事項</h2>
  <ul contenteditable="true">{NEXT_ACTIONS_ITEMS}</ul>
</section>

<section id="meeting-notes" class="notes">
  <h2>4. 打ち合わせメモ</h2>
  <div contenteditable="true" data-placeholder="ここに打ち合わせ中のメモを書き込めます"></div>
</section>

<aside id="toolbar">
  <button id="toggle-edit">編集モード: ON</button>
  <button id="save-html">保存して書き出し</button>
</aside>
```

## スタイル方針

- カラー: ネイビー `#1f3a5f` / グレー `#5b6470` / 白 / 薄ブルー背景アクセント `#f2f5f9`
- フォント: `-apple-system, BlinkMacSystemFont, "Segoe UI", "Hiragino Sans", sans-serif`
- 印刷向け media query で操作バー (`#toolbar`) を非表示
- contenteditable 領域: ホバーで薄い枠線、focus で青枠
- メモ欄 (`#meeting-notes`): 黄色付箋風の背景 `#fffbe6`
- 全 CSS をインライン化、画像は使用しない
- 絵文字・アイコンは使わない（業務文書らしさ優先）

## 保存ボタンの挙動

```text
1. document.documentElement.cloneNode(true) で複製
2. クローン側で:
   - <aside id="toolbar"> を削除
   - 全要素から contenteditable 属性を削除
   - 編集用 <script> を削除
   - data-placeholder 属性を削除
3. outerHTML を Blob (type="text/html") 化
4. <a download="{元ファイル名}-edited-HHMMSS.html"> を生成 → click() 起動
5. 元ファイルは触らない (上書きしない)
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
2. **Before/After は具体的に**: 「動かなかった」「動くようになった」では弱い。状態の差分を業務語彙で具体的に書く。
3. **メモ欄は空でスタート**: AI が予想で埋めない。
4. **PII 除外**: セッション中の個人情報（氏名・連絡先等）は出力に含めない。マスキング。
5. **空セッション保護**: 報告内容を抽出できない（純粋に雑談・調査のみで成果物がないセッション等）の場合は HTML を生成せず「報告対象の作業が見当たりません」と通知して終了。
6. **再生成では上書きしない**: タイムスタンプ付きファイル名で別ファイルとして保存。

## ファイル配置

- skill 本体: `/Users/snakashima/dotfiles/claude/skills-src/ops/share-report/SKILL.md`
- symlink: `/Users/snakashima/dotfiles/claude/skills/share-report → ../skills-src/ops/share-report`
- 出力先: `~/Documents/reports/session-report-YYYY-MM-DD-HHMM.html`
- カテゴリは `ops`（english-log / handover / eod など報告系と同列）

## エラーハンドリング

| ケース                         | 挙動                                                          |
| ------------------------------ | ------------------------------------------------------------- |
| 報告対象の作業がない           | HTML を生成せず通知のみ「報告対象の作業が見当たりません」     |
| `~/Documents/reports/` が無い  | 自動作成                                                      |
| `--to` で指定したディレクトリが存在しない | エラー表示で中止（自動作成しない、誤指定保護）        |
| `open` コマンドが失敗          | 警告のみ。ファイル保存は成功扱い                              |
| 既に同名ファイルが存在         | ファイル名末尾にミリ秒 or `-2`, `-3` ... を付与して衝突回避   |

## テスト方針

skill は宣言的ロジックが中心のため、検証は以下の手動チェックで行う：

1. **happy path**: 1セッション分の作業後に `/share-report` を実行 → ファイル生成 → ブラウザ表示 → 編集 → 保存 → ダウンロード版 HTML が意図通り（編集UI削除済み）
2. **空セッション**: 起動直後に何もせず `/share-report` → 「報告対象の作業が見当たりません」が出ること
3. **業務語彙チェック**: 出力 HTML 内に `.py`, `.ts`, `git`, `npm`, `linear`, ファイルパス等のキーワードが含まれないこと
4. **PII チェック**: テストとして個人名を含むセッションを行い、出力に氏名がマスキングされていること
5. **オフライン動作**: 生成 HTML をオフライン環境で開いて全機能（編集 / 保存）が動作すること
6. **印刷プレビュー**: ブラウザの印刷プレビューで操作バーが非表示になっていること
7. **再実行**: 同じセッション内で2回連続実行しても上書きされず別ファイルが作られること

## スコープ外（YAGNI）

- 複数テンプレ切替（社外用/社内用など）
- 既存レポートへの追記マージ
- Slack/Teams への自動アップロード
- メモ欄の Markdown レンダリング
- 編集履歴の version 管理
- レポート間のリンク・参照
- 多言語対応（日本語固定）

## 関連 skill

- `handover`: セッション全体（技術詳細含む）を Claude 自身が引き継ぐためのファイル。技術者向け。
- `learn`: 技術学習材料を `docs/learnings/` に永続化。技術者向け。
- `english-log`: 英語学習材料を Obsidian に蓄積。学習者向け。
- `eod`: 1日の作業の締め処理。デイリーログ等。

`share-report` は上記いずれとも異なる「非エンジニア向け業務報告」専用の出力先を持つ。
