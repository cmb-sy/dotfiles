# /share-report Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** セッション内容を業務サイドのステークホルダーへ Slack/Teams 添付で共有できる単一 HTML 報告書として出力する `/share-report` skill を新設する。報告書は contenteditable によりブラウザ内で直接編集でき、画面共有しながら書き込む打ち合わせメモ欄を備える。

**Architecture:** Claude 自身が現在のセッションを LLM 推論で抽出・業務語彙へ翻訳し、ファイル分離された HTML テンプレート（CSS/JS インライン）に変数置換して `~/Documents/reports/` に書き出す。生成後に macOS `open` でブラウザプレビュー。保存ボタンは現在の DOM をクローンして編集 UI を除去した版を Blob ダウンロードする。

**Tech Stack:** Markdown フロントマター付き Skill 定義 / Vanilla HTML5 + CSS3 + Vanilla JS (フレームワーク不使用) / macOS `open` / Bash + symlink

**Spec:** `docs/superpowers/specs/2026-06-15-share-report-design.md`

---

## File Structure

```
claude/
├── skills-src/ops/share-report/
│   ├── SKILL.md          # skill 指示書 (Claude が読む処理フロー)
│   └── template.html     # HTML テンプレート (変数プレースホルダ入り)
└── skills/
    └── share-report → ../skills-src/ops/share-report   # symlink
```

**責務分割:**
- `SKILL.md`: フロントマター + 抽出ロジック・業務語彙翻訳ガイド・テンプレ展開手順・引数仕様・エラーハンドリング
- `template.html`: HTML 構造 + インライン CSS + 編集 UI の JS。Claude が Read してプレースホルダを置換するだけの「データ」として扱う

**変数プレースホルダ:**
- `{{TITLE}}` — タイトル文字列
- `{{DATE}}` — YYYY-MM-DD
- `{{SUMMARY_BODY}}` — 依頼サマリ・背景の HTML 断片
- `{{BEFORE_AFTER_ROWS}}` — Before/After テーブルの `<tr>` 列
- `{{NEXT_ACTIONS_ITEMS}}` — 残課題の `<li>` 列

---

## Task 1: skill ディレクトリ作成と symlink セットアップ

**Files:**
- Create: `claude/skills-src/ops/share-report/SKILL.md` (空ファイル)
- Create: `claude/skills-src/ops/share-report/template.html` (空ファイル)
- Create: `claude/skills/share-report` (symlink)

- [ ] **Step 1: ディレクトリ作成**

```bash
mkdir -p /Users/snakashima/dotfiles/claude/skills-src/ops/share-report
touch /Users/snakashima/dotfiles/claude/skills-src/ops/share-report/SKILL.md
touch /Users/snakashima/dotfiles/claude/skills-src/ops/share-report/template.html
```

- [ ] **Step 2: symlink 作成**

```bash
cd /Users/snakashima/dotfiles/claude/skills
ln -s ../skills-src/ops/share-report share-report
```

- [ ] **Step 3: symlink が解決することを確認**

Run: `ls -la /Users/snakashima/dotfiles/claude/skills/share-report`
Expected: `share-report -> ../skills-src/ops/share-report` と表示される

Run: `ls /Users/snakashima/dotfiles/claude/skills/share-report/`
Expected: `SKILL.md  template.html` の 2 ファイルが見える

- [ ] **Step 4: コミット**

```bash
cd /Users/snakashima/dotfiles
git add claude/skills/share-report claude/skills-src/ops/share-report/
git commit -m "feat(share-report): skill ディレクトリと symlink を初期化"
```

---

## Task 2: HTML テンプレートの骨格とインライン CSS

**Files:**
- Modify: `claude/skills-src/ops/share-report/template.html` (空 → 骨格)

- [ ] **Step 1: template.html の骨格を書き込む**

`/Users/snakashima/dotfiles/claude/skills-src/ops/share-report/template.html` に以下の内容を書く（変数プレースホルダ `{{...}}` はそのまま保持）:

```html
<!DOCTYPE html>
<html lang="ja">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{{TITLE}}</title>
  <style>
    :root {
      --navy: #1f3a5f;
      --gray: #5b6470;
      --bg-accent: #f2f5f9;
      --note-bg: #fffbe6;
      --border: #d8dde3;
      --focus: #2a6df4;
    }
    * { box-sizing: border-box; }
    html, body {
      margin: 0;
      padding: 0;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Hiragino Sans", "Noto Sans JP", sans-serif;
      color: #222;
      background: #fff;
      line-height: 1.7;
    }
    body { padding: 40px 56px 120px; max-width: 880px; margin: 0 auto; }
    header { border-bottom: 3px solid var(--navy); padding-bottom: 16px; margin-bottom: 32px; }
    header h1 { color: var(--navy); margin: 0 0 8px; font-size: 26px; }
    header .meta { color: var(--gray); font-size: 14px; }
    section { margin-bottom: 36px; }
    section h2 {
      color: var(--navy);
      font-size: 18px;
      border-left: 4px solid var(--navy);
      padding-left: 10px;
      margin: 0 0 14px;
    }
    [contenteditable="true"] {
      border: 1px dashed transparent;
      padding: 8px 12px;
      border-radius: 4px;
      transition: border-color 0.15s, background 0.15s;
    }
    [contenteditable="true"]:hover { border-color: var(--border); }
    [contenteditable="true"]:focus { border-color: var(--focus); outline: none; background: #fafcff; }
    [contenteditable="true"][data-placeholder]:empty::before {
      content: attr(data-placeholder);
      color: #aab;
    }
    table { width: 100%; border-collapse: collapse; }
    th, td { border: 1px solid var(--border); padding: 12px 14px; vertical-align: top; text-align: left; }
    th { background: var(--bg-accent); color: var(--navy); font-weight: 600; width: 50%; }
    ul { padding-left: 22px; margin: 0; }
    ul li { margin-bottom: 6px; }
    #meeting-notes { background: var(--note-bg); padding: 18px 22px; border-radius: 6px; border: 1px solid #f0e6a5; }
    #meeting-notes h2 { border-left-color: #c79b00; color: #7a5c00; }
    #meeting-notes [contenteditable="true"] { min-height: 80px; }
    #toolbar {
      position: fixed; bottom: 16px; right: 16px;
      background: #fff; border: 1px solid var(--border); border-radius: 8px;
      box-shadow: 0 4px 16px rgba(0,0,0,0.08);
      padding: 10px 14px; display: flex; gap: 8px; z-index: 999;
    }
    #toolbar button {
      font: inherit; padding: 8px 14px; border: 1px solid var(--navy); background: #fff;
      color: var(--navy); border-radius: 4px; cursor: pointer;
    }
    #toolbar button:hover { background: var(--navy); color: #fff; }
    #toolbar button.primary { background: var(--navy); color: #fff; }
    #toolbar button.primary:hover { background: #142a47; }
    body.preview [contenteditable] { border-color: transparent !important; background: transparent !important; }
    @media print {
      #toolbar { display: none; }
      body { padding: 20px; }
    }
  </style>
</head>
<body>
  <header>
    <h1>{{TITLE}}</h1>
    <div class="meta">{{DATE}}</div>
  </header>

  <section id="summary">
    <h2>1. ご依頼のサマリと背景</h2>
    <div contenteditable="true">{{SUMMARY_BODY}}</div>
  </section>

  <section id="before-after">
    <h2>2. 実現したこと</h2>
    <table>
      <thead><tr><th>変更前 (Before)</th><th>変更後 (After)</th></tr></thead>
      <tbody contenteditable="true">{{BEFORE_AFTER_ROWS}}</tbody>
    </table>
  </section>

  <section id="next-actions">
    <h2>3. 残課題・次のアクション・確認事項</h2>
    <ul contenteditable="true">{{NEXT_ACTIONS_ITEMS}}</ul>
  </section>

  <section id="meeting-notes">
    <h2>4. 打ち合わせメモ</h2>
    <div contenteditable="true" data-placeholder="ここに打ち合わせ中のメモを書き込めます"></div>
  </section>

  <aside id="toolbar">
    <button id="toggle-edit" type="button">編集モード: ON</button>
    <button id="save-html" type="button" class="primary">保存して書き出し</button>
  </aside>

  <!-- JS は Task 3 で追加 -->
</body>
</html>
```

- [ ] **Step 2: ブラウザで開いて表示確認**

Run: `cp /Users/snakashima/dotfiles/claude/skills-src/ops/share-report/template.html /tmp/share-report-preview.html && open /tmp/share-report-preview.html`

Expected: ブラウザが開き、以下が見える:
- ヘッダー: `{{TITLE}}` がそのまま表示、その下に `{{DATE}}`
- 4 つのセクション (依頼サマリ / 実現したこと / 残課題 / 打ち合わせメモ)
- 打ち合わせメモは黄色付箋風の背景
- 右下に「編集モード: ON」「保存して書き出し」のボタンバー
- contenteditable 領域にホバーすると点線枠が現れる
- 印刷プレビュー (Cmd+P) で右下のボタンバーが消える

- [ ] **Step 3: コミット**

```bash
cd /Users/snakashima/dotfiles
git add claude/skills-src/ops/share-report/template.html
git commit -m "feat(share-report): HTML テンプレートの骨格とインライン CSS を実装"
```

---

## Task 3: 編集 UI と保存ボタンの JavaScript

**Files:**
- Modify: `claude/skills-src/ops/share-report/template.html` (末尾 `</body>` の直前に `<script>` ブロック追加)

- [ ] **Step 1: `</body>` 直前に `<script>` を追加**

`template.html` の `<!-- JS は Task 3 で追加 -->` のコメント行を以下に置換する:

```html
  <script>
    (function () {
      const toggleBtn = document.getElementById('toggle-edit');
      const saveBtn = document.getElementById('save-html');
      let editing = true;

      function applyEditingState() {
        document.querySelectorAll('[contenteditable]').forEach(el => {
          el.setAttribute('contenteditable', String(editing));
        });
        document.body.classList.toggle('preview', !editing);
        toggleBtn.textContent = '編集モード: ' + (editing ? 'ON' : 'OFF');
      }

      toggleBtn.addEventListener('click', () => {
        editing = !editing;
        applyEditingState();
      });

      function pad(n) { return String(n).padStart(2, '0'); }
      function timestamp() {
        const d = new Date();
        return d.getFullYear() + pad(d.getMonth() + 1) + pad(d.getDate())
          + '-' + pad(d.getHours()) + pad(d.getMinutes()) + pad(d.getSeconds());
      }

      saveBtn.addEventListener('click', () => {
        const clone = document.documentElement.cloneNode(true);

        // 編集 UI を除去
        const toolbar = clone.querySelector('#toolbar');
        if (toolbar) toolbar.remove();

        // contenteditable と placeholder を除去
        clone.querySelectorAll('[contenteditable]').forEach(el => el.removeAttribute('contenteditable'));
        clone.querySelectorAll('[data-placeholder]').forEach(el => el.removeAttribute('data-placeholder'));

        // 編集用 <script> を除去 (このスクリプト自身)
        clone.querySelectorAll('script').forEach(s => s.remove());

        const html = '<!DOCTYPE html>\n' + clone.outerHTML;
        const blob = new Blob([html], { type: 'text/html;charset=utf-8' });
        const url = URL.createObjectURL(blob);

        const currentName = (location.pathname.split('/').pop() || 'report.html').replace(/\.html?$/i, '');
        const a = document.createElement('a');
        a.href = url;
        a.download = currentName + '-edited-' + timestamp() + '.html';
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        setTimeout(() => URL.revokeObjectURL(url), 1000);
      });
    })();
  </script>
```

- [ ] **Step 2: ブラウザで編集 → 保存の e2e 動作確認**

Run: `cp /Users/snakashima/dotfiles/claude/skills-src/ops/share-report/template.html /tmp/share-report-preview.html && open /tmp/share-report-preview.html`

Expected: ブラウザ上で以下が動作する:
1. ヘッダーをクリック以外の本文セクション (`{{SUMMARY_BODY}}` の中身) をクリックすると入力可能になり、文字を打てる
2. 打ち合わせメモ欄にテキストを入力できる
3. 「編集モード: ON」を押すと「編集モード: OFF」に変わり、contenteditable 枠線が消える。もう一度押すと ON に戻る
4. 「保存して書き出し」を押すとブラウザのダウンロードに `share-report-preview-edited-YYYYMMDD-HHMMSS.html` が落ちる
5. ダウンロードした HTML をテキストエディタで開くと、`contenteditable` 属性も `<aside id="toolbar">` も `<script>` も含まれていない (cleaned)

- [ ] **Step 3: ダウンロード後 HTML を再度ブラウザで開いて静的表示できることを確認**

Run: `open ~/Downloads/share-report-preview-edited-*.html` (最新のものを開く)

Expected: 編集した内容がそのまま静的に表示され、編集 UI（ボタンバー）は無く、本文をクリックしても編集できない。

- [ ] **Step 4: コミット**

```bash
cd /Users/snakashima/dotfiles
git add claude/skills-src/ops/share-report/template.html
git commit -m "feat(share-report): 編集モード切替と Blob ダウンロード保存を実装"
```

---

## Task 4: SKILL.md の本体（処理フロー、業務語彙翻訳ガイド、引数仕様、エラーハンドリング）

**Files:**
- Modify: `claude/skills-src/ops/share-report/SKILL.md` (空 → 完成版)

- [ ] **Step 1: SKILL.md に全内容を書き込む**

`/Users/snakashima/dotfiles/claude/skills-src/ops/share-report/SKILL.md` に以下を書く:

````markdown
---
name: share-report
description: >-
  現在のセッションで実施した依頼の結果を、業務部門のステークホルダー（PM・営業・運用担当など、非エンジニア）向けに
  Slack/Teams 添付で共有できる単一 HTML 報告書として出力する。技術詳細を完全に除外し、業務語彙のみで構成。
  contenteditable によりブラウザ内で直接編集でき、画面共有しながら書き込む打ち合わせメモ欄を備える。
argument-hint: "[--title \"X 機能改善報告\"] [--to PATH] [--no-open] [--dry-run]"
user-invocable: true
---

セッション内容を業務サイドのステークホルダーへ共有する HTML 報告書を生成する。

## 前提

- macOS（`open` コマンド使用）
- 出力先デフォルト: `~/Documents/reports/`
- 技術詳細（ファイルパス・コマンド・コード・ライブラリ名・GitHub/Linear ID 等）は **一切出力に含めない**

## 処理フロー

### Step 1: セッション内容の抽出と業務語彙への翻訳

このセッションで Claude が行った作業を以下の 3 カテゴリに整理する:

**A. 依頼のサマリ・背景** (`{{SUMMARY_BODY}}`):
- ユーザーが「何をしてほしいと依頼したか」を業務サイド視点で要約
- 背景・動機があれば併記（「以前はこういう手間があった」「これが課題だった」など）
- 1〜3 段落、`<p>` 要素で構成

**B. 実現したこと (Before / After)** (`{{BEFORE_AFTER_ROWS}}`):
- 変更前と変更後の状態を業務語彙で具体的に対比
- 各行 `<tr><td>Before の状態</td><td>After の状態</td></tr>` 形式
- 2〜5 行を目安

**C. 残課題・次のアクション** (`{{NEXT_ACTIONS_ITEMS}}`):
- 未実装部分、追加で確認が必要な点、依頼者へのお願い事項
- 各項目 `<li>...</li>` 形式
- 0〜5 項目（無ければ「現時点で残課題はありません」を 1 項目）

### 業務語彙翻訳ガイド

技術用語を業務サイド読み手にわかる表現に置き換える。例:

| 技術表現 (出さない)                                | 業務表現 (こう書く)                            |
| -------------------------------------------------- | ---------------------------------------------- |
| Slack の Bot トークンを env に追加                 | Slack 連携の設定情報を整備                     |
| `claude/settings.json` を更新                      | Claude の動作設定を更新                        |
| pre-commit hook を追加                             | コミット時の自動チェックを追加                 |
| linear-cli で issue を作成                         | Linear に課題を登録                            |
| ts のビルドエラーを修正                            | 起動時のエラーを修正                           |
| n+1 クエリを解消                                   | 一覧画面の表示速度を改善                       |
| symlink で設定を共有                               | 設定ファイルを共通化                           |
| `pytest -k foo` でテスト                           | 関連機能の動作を検証                           |

**禁止表現:**
- ファイル拡張子 (`.py`, `.ts`, `.html` 等)
- コマンド名 (`git`, `npm`, `pytest`, `make` 等)
- Linear/GitHub の ID（`KUNST-123`, `#456` 等）
- ハッシュ・SHA・コミットメッセージの引用
- ライブラリ名 (`yfinance`, `playwright` 等)
- 純粋に技術的なエラー文言

業務サイド読み手が「で、何ができるようになるの？」「私の業務がどう変わるの？」を判断できる表現にする。

### Step 2: テンプレート読み込みと変数置換

1. `/Users/snakashima/dotfiles/claude/skills-src/ops/share-report/template.html` を Read で読み込む
2. 以下のプレースホルダを置換する:
   - `{{TITLE}}` → `--title` 引数または「<対象機能名> ご報告 — YYYY-MM-DD」をデフォルトで生成
   - `{{DATE}}` → 今日の日付（YYYY-MM-DD 形式）
   - `{{SUMMARY_BODY}}` → Step 1-A で生成した HTML 断片
   - `{{BEFORE_AFTER_ROWS}}` → Step 1-B で生成した `<tr>` 列
   - `{{NEXT_ACTIONS_ITEMS}}` → Step 1-C で生成した `<li>` 列

**HTML エスケープ:** 本文中の `<`, `>`, `&` は `&lt;`, `&gt;`, `&amp;` に変換する。ただし `<p>`, `<tr>`, `<td>`, `<li>` などの構造タグ自体は生かす（自分で生成するため安全）。

### Step 3: 保存

1. 出力先ディレクトリを決定:
   - `--to PATH` が指定されていればその親ディレクトリ
   - 未指定なら `~/Documents/reports/`
2. ディレクトリが存在しなければ作成（`--to` で明示指定された場合は親ディレクトリ不在ならエラー）
3. ファイル名を決定:
   - `--to PATH` 指定: その PATH
   - 未指定: `session-report-YYYY-MM-DD-HHMM.html`
4. 同名ファイルが既に存在する場合は末尾に `-2`, `-3` ... を付けて衝突回避
5. 置換後の HTML をファイルに書き込む

### Step 4: プレビューと案内

1. `--no-open` でなければ `open <path>` でブラウザを開く
2. ユーザーに以下を伝える:
   - 保存先パス
   - 「ブラウザ上で各セクションを直接編集できます。画面共有中に受け取ったコメントは『打ち合わせメモ』欄に書き込めます」
   - 「編集が完了したら『保存して書き出し』ボタンを押すと、編集 UI を除去した版がダウンロードされます。そのファイルを Slack/Teams に添付してください」

## 引数

| 引数              | 説明                                                              |
| ----------------- | ----------------------------------------------------------------- |
| `--title "..."`   | レポートタイトルを上書き                                          |
| `--to PATH`       | 出力先パスを上書き (絶対パス推奨)                                 |
| `--no-open`       | 生成後にブラウザを自動で開かない                                  |
| `--dry-run`       | HTML を生成せず、Step 1 で抽出したドラフトを Markdown でチャットに提示するのみ |

## ルール

1. **業務語彙のみ**: 上記「業務語彙翻訳ガイド」「禁止表現」を厳守。技術アーティファクトを一切出さない。
2. **メモ欄は空でスタート**: `data-placeholder` のままにし、AI が予想で埋めない。
3. **PII 除外**: 個人情報は CLAUDE.md「PII Protection」のマスキング規則（例: `田中***`, `090-****-****`）に従う。
4. **空セッション保護**: 報告対象の作業が抽出できない（雑談・調査のみ等）場合は HTML を生成せず「報告対象の作業が見当たりません」と通知して終了。
5. **再生成では上書きしない**: タイムスタンプ付き別ファイル、または衝突回避 suffix で別ファイルを作る。
6. **過剰装飾禁止**: 絵文字・アイコンを本文に入れない（業務文書らしさ優先）。

## エラーハンドリング

| ケース                                       | 挙動                                                             |
| -------------------------------------------- | ---------------------------------------------------------------- |
| 報告対象の作業が見当たらない                 | HTML 非生成、通知のみ                                            |
| `~/Documents/reports/` が無い                | 自動作成                                                         |
| `--to` の親ディレクトリが存在しない          | エラー表示で中止（自動作成しない、誤指定保護）                   |
| `open` コマンドが失敗                        | 警告のみ、ファイル保存は成功扱い                                 |
| 同名ファイル存在                             | 末尾に `-2`, `-3` ... を付与して衝突回避                         |
| template.html が見つからない                 | エラー: skill のセットアップが壊れている旨を伝えて中止           |

## 関連

- `handover`: 技術者向けのセッション引継ぎ（技術詳細を含む）
- `learn`: 技術学習材料を `docs/learnings/` に永続化
- `english-log`: 英語学習材料を Obsidian に蓄積
- `eod`: 1日の作業の締め処理
````

- [ ] **Step 2: SKILL.md が正しく読めることを Read で確認**

Run: `head -20 /Users/snakashima/dotfiles/claude/skills-src/ops/share-report/SKILL.md`

Expected: YAML フロントマター（`name: share-report` を含む）が表示される

- [ ] **Step 3: コミット**

```bash
cd /Users/snakashima/dotfiles
git add claude/skills-src/ops/share-report/SKILL.md
git commit -m "feat(share-report): SKILL.md に処理フローと業務語彙翻訳ガイドを実装"
```

---

## Task 5: e2e 動作確認（実セッションで /share-report を起動）

**Files:** 動作確認のみ、コード変更なし

- [ ] **Step 1: 新しいセッションで skill が認識されるか確認**

`/share-report` を実行できる前に Claude Code を再起動 (`/exit` → 再起動) する必要があるかを確認。

Run: `ls -la /Users/snakashima/.claude/skills/share-report 2>/dev/null || ls -la /Users/snakashima/dotfiles/claude/skills/share-report`

Expected: symlink が `../skills-src/ops/share-report` を指していること

**注:** 既存 skill (`english-log` 等) と同じ場所に同じ symlink 構造で配置されていれば、再起動なしで認識される想定（既存セッションが何らかの skill レジストリをキャッシュしている場合は再起動が必要）。

- [ ] **Step 2: happy path e2e: 1セッション分の作業後に `/share-report` を実行**

事前準備: テスト用の「業務的に意味のある変更」を伴うセッションを 1 つ用意する（または既存セッションで起動）。

Run: ユーザーがセッション内で `/share-report` を発火

Expected:
- `~/Documents/reports/session-report-YYYY-MM-DD-HHMM.html` が生成される
- ブラウザが自動で開く
- 4 セクションすべてに業務語彙で内容が入っている（依頼サマリ / Before-After テーブル / 残課題 / 空の打ち合わせメモ）
- ファイル内に技術アーティファクトキーワードが含まれない

- [ ] **Step 3: 業務語彙チェック（grep で禁止キーワードが含まれないこと）**

Run:

```bash
LATEST=$(ls -t ~/Documents/reports/session-report-*.html | head -1)
echo "Checking: $LATEST"
grep -E '\.(py|ts|tsx|js|jsx|html|json|sh|md)\b|\bgit\b|\bnpm\b|\bpytest\b|\bclaude-code\b|KUNST-[0-9]|#[0-9]+' "$LATEST" && echo "FOUND BANNED" || echo "OK (no banned tokens)"
```

Expected: `OK (no banned tokens)`

**注:** false positive がある場合（例: 業務文中に「git」が一般語として出ること）は妥当性をレビューする。基本的には技術文脈での出現を見つけたい。

- [ ] **Step 4: ブラウザ編集 → 保存ボタン動作確認**

ブラウザ上で:
1. 依頼サマリのテキストを少し書き換える
2. 打ち合わせメモ欄に何か書き込む
3. 「保存して書き出し」を押す

Expected:
- `~/Downloads/session-report-YYYY-MM-DD-HHMM-edited-YYYYMMDD-HHMMSS.html` が落ちる
- ダウンロードした HTML を `open` で開くと、編集内容が反映されており、編集 UI ボタンバーは表示されない

- [ ] **Step 5: 空セッション保護の動作確認**

純粋に雑談だけのセッション（コード変更なし、報告対象の作業がない状態）で `/share-report` を実行。

Expected: HTML は生成されず、「報告対象の作業が見当たりません」相当の通知のみ。

- [ ] **Step 6: `--no-open` 動作確認**

Run: `/share-report --no-open` を発火

Expected: HTML は生成されるが、ブラウザは自動で開かない。

- [ ] **Step 7: 再実行時の衝突回避確認**

同じ分内に `/share-report` を 2 回連続実行。

Expected: 2回目は `-2` または別ファイル名で別ファイルが生成され、1 回目のファイルは上書きされない。

- [ ] **Step 8: `--dry-run` 動作確認**

Run: `/share-report --dry-run` を発火

Expected: HTML は生成されず、ドラフト内容（依頼サマリ・Before/After・残課題）が Markdown 形式でチャットに表示される。

- [ ] **Step 9: 動作確認結果をコミット（必要なら微修正）**

動作確認中に発見した不具合があればその場で SKILL.md / template.html を修正してコミット。

```bash
cd /Users/snakashima/dotfiles
# 修正があれば
git add claude/skills-src/ops/share-report/
git commit -m "fix(share-report): e2e 動作確認で見つかった <内容> を修正"
```

修正不要なら本タスクで commit は発生しない。

---

## Self-Review Checklist

Spec requirements との対応:

- [x] **対象=業務サイド・共有=Slack/Teams 添付** → Task 4 SKILL.md「業務語彙翻訳ガイド」「禁止表現」で担保
- [x] **3 セクション（依頼サマリ/Before-After/残課題）** → Task 2 template.html, Task 4 Step 1-A/B/C
- [x] **技術詳細を完全除外** → Task 4 翻訳ガイド + Task 5 Step 3 grep 検証
- [x] **出力 `~/Documents/reports/`** → Task 4 Step 3
- [x] **ブラウザ自動プレビュー** → Task 4 Step 4
- [x] **contenteditable 編集** → Task 2 template, Task 3 JS
- [x] **打ち合わせメモ欄** → Task 2 template (#meeting-notes)
- [x] **保存ボタンで編集 UI 除去版ダウンロード** → Task 3 JS
- [x] **業務文書風スタイル** → Task 2 インライン CSS
- [x] **引数 (--title / --to / --no-open / --dry-run)** → Task 4 引数表 + Task 5 Step 6,8
- [x] **PII 除外** → Task 4 ルール #3
- [x] **空セッション保護** → Task 4 ルール #4 + Task 5 Step 5
- [x] **再生成では上書きしない** → Task 4 ルール #5, エラーハンドリング表, Task 5 Step 7
- [x] **絵文字・アイコン使用しない** → Task 4 ルール #6
- [x] **単一HTML完結・外部依存なし** → Task 2 でインライン CSS、Task 3 でインライン JS

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-15-share-report.md`. Two execution options:

1. **Subagent-Driven (recommended)** - Fresh subagent per task, review between tasks, fast iteration
2. **Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
