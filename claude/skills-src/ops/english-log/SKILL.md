---
name: english-log
description: >-
  このセッション中に Claude が指摘した英語の訂正を抽出し、Obsidian vault の
  03_skillup/english/YYYY-MM-DD.md に追記する。CLAUDE.md「英語学習補助」ルールが
  生成する訂正のアーカイブ用途。
argument-hint: "[--date YYYY-MM-DD]  (省略時は今日)"
user-invocable: true
---

このセッション中に Claude が指摘した英語の訂正を抽出し、Obsidian vault の
`03_skillup/english/YYYY-MM-DD.md` に追記する。

## 前提

- CLAUDE.md の「英語学習補助」セクションが有効であること。これが訂正を生成する元。
- Obsidian vault は `/Users/snakashima/Documents/obsidian/`（git リポジトリ、private）。

## 処理フロー

### Step 1: 訂正の抽出

このセッションで Claude が user に対して与えた英語訂正を抽出する。対象は:
- ASSISTANT 発言で「X → Y」の形で英語表現を直したもの
- "Note:" や説明的フレーズで自然な英語を提案したもの
- 同じパターン再発の指摘

抽出対象は **このセッション内** のみ。過去セッションには遡らない。

抽出時の注意:
- USER 発言からの引用・コードブロック内の例は対象外（user の発言を訂正したものに限る）
- 技術的回答に付帯した短い注記も含める
- 1件もなければ "No corrections in this session" と通知して終了

### Step 2: フォーマット

抽出した各訂正を以下のフォーマットに整形:

```markdown
### N. "<元の表現>" → "<正しい表現>"
- Issue: <何が誤りか、1〜2文>
- Pattern: <カテゴリ。preposition / question-order / verb-tense / collocation / vocabulary など>
```

末尾に該当セッションで観察した Pattern まとめを 1〜2 行で添える。

### Step 3: 出力先の決定

- ベースパス: `/Users/snakashima/Documents/obsidian/03_skillup/english/`
- ファイル名: `YYYY-MM-DD.md`（今日の日付。`--date` 引数で上書き可）
- ディレクトリが無ければ作成する。

### Step 4: 書込み

- 新規ファイル: 冒頭に `# English Corrections — YYYY-MM-DD` を置き、その下に `## HH:MM session`（現在時刻、24h）と Step 2 の本文。
- 既存ファイル: 末尾に空行を入れて `## HH:MM session` セクションを追記する。

書込み前にユーザーに「N 件の訂正を <path> に追記します」と確認する。承認後に書込み。

### Step 5: 報告

- 追加した訂正件数
- 書込み先ファイルパス
- vault のコミット/プッシュは `/eod` に任せる（このスキルは自動 commit しない）

## ルール

1. **このセッション限定**: 過去のセッションファイルを読みに行かない。
2. **訂正のみが対象**: 一般的な会話への返答や技術解説は含めない。
3. **vault は git リポジトリだが自動コミットしない**: `/eod` に統合されている。
4. **PII 除外**: 訂正対象の文に個人情報が含まれていたらマスキングしてから書く。
5. **重複防止**: 同日同セッションで複数回 invoke されたら、追加分のみを新セクションとして追記する。
