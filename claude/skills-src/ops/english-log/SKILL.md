---
name: english-log
description: >-
  このセッションで受けた英語の訂正・英訳例を Obsidian に記録したいときに使う。
  Claude が与えた両方向の学習材料（英語入力時の `"X" → "Y"` 訂正 + 日本語入力時の英訳例）を抽出し、
  vault の 03_skillup/english/YYYY-MM-DD.md に追記する。日付上書きは本文の Options を参照。
argument-hint: "[--date YYYY-MM-DD]  (省略時は今日)"
user-invocable: true
---

このセッション中に Claude が与えた英語学習材料を抽出し、Obsidian vault の
`03_skillup/english/YYYY-MM-DD.md` に追記する。対象は2方向:

- **英語訂正**: ユーザーが英語で話しかけたときに Claude が示した `"X" → "Y"` 形式の訂正
- **英訳教示**: ユーザーが日本語で話しかけたときに Claude が示した `In English: ...` の英訳例

## Options

| Option | 効果 |
|--------|------|
| `--date YYYY-MM-DD` | 追記先ファイルの日付を上書きする（省略時は今日） |

## 前提

- CLAUDE.md の「英語学習補助」セクションが有効であること。これが訂正を生成する元。
- Obsidian vault は `$HOME/develop/obsidian/`（git リポジトリ、private）。

## 処理フロー

### Step 1: 学習材料の抽出

このセッションで Claude が user に対して与えた英語学習材料を2カテゴリに分けて抽出する:

**A. 英語訂正**（user が英語で話したとき）:
- ASSISTANT 発言で「X → Y」の形で英語表現を直したもの
- "Note:" や説明的フレーズで自然な英語を提案したもの
- 同じパターン再発の指摘

**B. 英訳教示**（user が日本語で話したとき）:
- ASSISTANT 発言で「In English: ...」や類似形式で英訳例を提示したもの
- 言い回しの解説（カジュアル/フォーマル、代替表現など）も含める

抽出対象は **このセッション内** のみ。過去セッションには遡らない。

抽出時の注意:
- USER 発言からの引用・コードブロック内の例は対象外（Claude が学習材料として提示したものに限る）
- 技術的回答に付帯した短い注記も含める
- A・B どちらも 1 件もなければ "No English learning material in this session" と通知して終了

### Step 2: フォーマット

カテゴリごとにセクションを作る。

**A. Corrections**（英語訂正があれば）:
```markdown
### N. "<元の表現>" → "<正しい表現>"
- Issue: <何が誤りか、1〜2文>
- Pattern: <カテゴリ。preposition / question-order / verb-tense / collocation / vocabulary など>
```

**B. Translations**（英訳教示があれば）:
```markdown
### N. 日本語: "<元の日本語表現>"
- In English: "<英訳>"
- Note: <自然な言い回し・代替表現・文体の違いなど。あれば 1〜2 文>
```

末尾に該当セッションで観察した Pattern まとめ（誤りカテゴリ・覚えておきたい表現）を 1〜3 行で添える。

### Step 3: 出力先の決定

- ベースパス: `$HOME/develop/obsidian/03_skillup/english/`
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
