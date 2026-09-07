---
name: distill-gain-latest-info
description: >-
  技術情報を「集めて得る」ときに使う情報収集スキル。watch モード（GitHub /
  サービス changelog / エンジニア発信 / ニュース / dotfiles peer を横断観測し
  Obsidian にダイジェスト蓄積）と research モード（トピックを Web + 自リポジトリ
  横断で深掘り）を持つ。フラグは本文の「起動」を参照。
argument-hint: "[watch [--only <scope>] [--target X] | research <topic>]"
user-invocable: true
---

<!-- distill-gain-latest-info = "gather intel" + "得る(gain)". A portmanteau: gathering and obtaining tech intel. -->

# distill-gain-latest-info — 情報収集スキル

技術情報を集めて得るための単一スキル。2 モードを持つ。

- **watch（レーダー）**: `sources.yaml` の監視先のうち今週まだ確認していないものだけを対象に、差分をダイジェスト化する
- **research（深掘り）**: トピックを Web 知見 × 自リポジトリ実態で調べる

watch の収集・ダイジェスト生成フェーズはユーザーに質問しない。対話が要る場面（改善提案の採否）は生成物に書いて返すだけに留め、承認は呼び出し元（`/eod` 本体、または直接起動した対話フロー）が行う。

**開始時アナウンス:** 「distill-gain-latest-info を開始します。」続けて選択されたモード/スコープを明示する。

## 起動

```
/distill-gain-latest-info                                   # 引数なし → 対話メニュー（デフォルト）
/distill-gain-latest-info watch                              # due な監視先のみ実行
/distill-gain-latest-info watch --only <scope> [--target X]  # 単一 scope、対象指定
/distill-gain-latest-info research <topic>                   # 深掘りを直接実行
```

- `<scope>`: `peers | github | services | engineers | news`（`sources.yaml` のトップレベルキーと一致）
- `--target X` は選択 scope 内の対象を X に限定する（peers なら handle、github なら repo、services/engineers なら name、news なら query）

ARGUMENTS をパースし、第 1 引数（`watch`/`research`）、`--only`、`--target` を抽出する。第 1 引数が無ければ対話メニューへ。

## 対話フロー（引数なし起動時）

AskUserQuestion は 1 問最大 4 択のため 2 段構成にする。人が直接起動した場合にのみ通る経路であり、`/eod` は常に `watch` を明示して呼ぶためこの経路を通らない。

**Q1「何をしますか?」**
1. 全ウォッチ（`sources.yaml` の due な監視先すべて）
2. scope を選んで watch
3. research（深掘り調査）

**Q2（Q1=2 のときのみ）「どの scope?」** `sources.yaml` の 5 scope（peers/github/services/engineers/news）から選ぶ。1 問 4 択の枠に収まらないため、5 番目は自由入力枠で拾う。

- scope を選んだら続けて**対象を追加質問**する（例: news → 「どのクエリ?」を `sources.yaml` の登録内容 + AI 推測候補 + 自由入力で提示）
- 選んだアドホック対象が `sources.yaml` に未登録なら、実行後に **「今後も watch 対象に追加しますか?」** を AskUserQuestion で確認 → YES で該当セクションに追記（単発 → 永続化）。ユーザー承認なしに追記しない

## watch: 収集フロー

### Step 1: Due 判定

`bin/gain-state due claude/skills/distill-gain-latest-info/sources.yaml` を実行し、`<scope>\t<key>` 形式の行を得る（リポジトリルートからの相対パス）。`--only`/`--target` があればここでその scope/key に絞り込む。

0 行なら「今週は全監視先を確認済み」（`--only` 指定時は「`<scope>` は今週確認済み」）と報告して終了する。**ダイジェストファイルは作らない。**

### Step 2: 収集（並列）

残った `<scope>\t<key>` を scope ごとにグルーピングし、scope 内は 1 対象 = 1 サブエージェント（`general-purpose`、自己完結プロンプト）で並列 dispatch する（メイン context 保護）。lookback window は 14 日固定とする（`gain-state due` が週次の頻度を保証するため、取りこぼし防止のバッファとして十分）。各エージェントは**構造化データ（YAML）**を返す。

| scope | 取得方法 | 信頼度 |
|---|---|---|
| peers | commit（`gh api /repos/{owner}/{name}/commits?since=<iso8601>`）+ 新規追加ファイル + 注目ファイル（README.md/Brewfile/`*.json`/`*.yaml`/`flake.nix`/`chezmoi*.toml`）更新有無 + star 数 | 高 |
| github | `gh api /repos/{repo}/commits?since=<iso>` + `/releases` | 高 |
| services | changelog URL を WebFetch → 直近 14 日以内のエントリ抽出 | 中〜高 |
| engineers | blog は RSS/Atom を WebFetch（無ければスクレイプにフォールバック）、SNS は WebSearch で直近の注目投稿 | blog 高 / SNS **低（best-effort）** |
| news | クエリごとに WebSearch → 影響度・新しさでフィルタ | 中 |

**peers の対象解決:** `key` は handle。`peers.overrides` に該当があればその `owner/name`、無ければ `<handle>/dotfiles`。`gh api /repos/{owner}/{name}` で存在確認し、404 は 1 行警告で skip する（skip 分は Step 4 の `gain-state record` を呼ばない）。

SNS 由来のエントリは必ず「信頼度低」ラベルを付す。取得ゼロは正常（「該当なし」と記載し、Step 4 の record は findings=0 で呼ぶ）。

### Step 3: 統合・分析（メイン実行、サブエージェントに投げない）

**既出照合:** `99_distill/情報収集/` の直近 3 日分のファイルの URL・タイトルと突合し、重複エントリを除外する。

残った候補それぞれに:
- **何が変わったか**: 一次情報を読んで書く（タイトルの引き写しにしない）。専門用語は「そもそも何か」を 1〜2 文で解説
- **自分の環境で何が変わるか**: `$HOME/dotfiles` を実 grep/find/ls で確認し（LLM 推測禁止）、該当する自リポジトリのファイル名まで名指しする
- **次の一手**: 試す / 様子見 / 関係なし のいずれかを選び、理由を添える

全 scope 合算で **3〜5 件**を選んで深掘り記述する。選ばれなかった候補は件名だけを 1 行で残す（見落としでないことを示すため）。

### Step 4: 記録・出力

`$HOME/develop/obsidian/99_distill/情報収集/YYYY-MM-DD.md` に書く（無ければ作成、同日ならファイルの既存見出しに追記し重複させない）。

処理した監視先ごとに `bin/gain-state record <scope> <key> <採用件数>` を呼ぶ。**採用 0 件でも呼ぶ**（「処理した」という記録自体が翌週までのクールダウンと `## 改善提案` の根拠になる）。

### 完了報告

```
distill-gain-latest-info watch 完了。対象 <n> / due <m>
記録先: 99_distill/情報収集/<date>.md
```

Step 1 で 0 行だった場合はその旨のみ報告する。

## research モード

トピックを受け取り並列で:
- **Web**: 既存 `deep-research` スキルを invoke（fan-out 検索 + adversarial verify + 出典付き）。利用不可なら内蔵 WebSearch で縮退し、その旨を明示。**縮退時も全主張に出典 URL を付ける**（実在確認済みのみ。確認できない主張は「未検証」と明記）
- **自リポ**: `code-explorer` 系サブエージェントで現リポジトリの関連構造・依存・既存実装を調査

オーケストレーターが両者を統合:
- 技術選定 → 導入可否・影響範囲・既存コードとの整合性
- 外部リポ理解 → 設計/実装の要約 + 自リポへの取り込みポイント

出力: `$HOME/develop/obsidian/99_distill/情報収集/YYYY-MM-DD.md` に `## Research: <topic>` 節として追記する。同日に watch を実行済みで既に `## 改善提案` 節がある場合は、その節の直前に挿入する（`## 改善提案` は常にファイル末尾に置く）。

## ダイジェストの構造（Obsidian）

出力は `99_distill/情報収集/YYYY-MM-DD.md` の 1 ファイルに一本化する。Obsidian の callout・表・Mermaid を活用し、以下の構造で書く。

**全 scope 共通の深さ原則:** 「何が起きたか（事実）」ではなく **「何がどう変わったか + なぜ重要か + 自分の環境でどう変わるか」** を主役にする。リリースノートやニュース見出しをそのまま訳しただけの項目は不可。

````markdown
---
date: YYYY-MM-DD
type: gain-digest
tags: [情報収集, tech-radar]
scopes: [peers, github, services, engineers, news]
---
# 情報収集 YYYY-MM-DD

> [!abstract] 今回の3行
> - 最重要トピックを3行以内で（読者が本文を読むかを決める材料）

## サマリー

| scope | 件数 | 最注目 | 次の一手 |
|---|---|---|---|
| GitHub | n | <item> | 試す/様子見/関係なし |

## GitHub

### owner/repo — <テーマ>

**何が変わったか**（4〜8文。差分を前後対比で書く）

**自分の環境で何が変わるか**: 実 grep/find/ls に基づく判定。該当ファイル名まで書く。

> [!tip] 次の一手: 試す
> 理由を2〜3文で。

**source**: <URL>

## サービス更新
## エンジニア発信（blog / SNS・信頼度低）
## ニュース
## peers（dotfiles 採用ワークフロー）

（見出しごとの構成は GitHub と同じ。処理したが選ばれなかった候補は件名のみ 1 行で列挙する）

## 改善提案

`~/.local/state/gain/sources.tsv` の `runs`/`findings` を根拠に挙げる。
- **実績の無い監視先**: 一定回数処理して findings が積み上がらない監視先（除外候補）
- **繰り返し現れた話題**: 直近数回のダイジェストを読み返し、複数回言及したテーマ（追加候補）

このスキル自身は適用しない。承認は呼び出し元が行う。
````

**callout の使い分け（次の一手と対応させる）:**

| 次の一手 | callout |
|---|---|
| 試す | `> [!tip]` |
| 様子見 | `> [!warning]` |
| 関係なし | `> [!quote]` |
| セキュリティ・障害系の注意情報 | `> [!danger]` |

**深さの基準:** 選ばれた 3〜5 件は 1 件あたり 10〜20 行を目安に、「何が変わったか」は前提概念から書く（CLAUDE.md 技術メモと同じ教育深度）。比較対象が3つ以上あるときは表を必須とする。Mermaid 図は構造・フローの理解を速めるときだけ使い、装飾目的では使わない。

- vault の commit/push はしない（`/eod` に委譲）

## エラーハンドリング

| 状況 | 対応 |
|---|---|
| `sources.yaml` が parse 不能 | 実行せず「sources.yaml の YAML が不正です（`key: []` と実体リストの共存に注意）」と該当箇所を添えて報告し終了 |
| scope のソース定義が空（`[]`） | 「<scope>: ソース未登録のためスキップ」と 1 行報告して次 scope へ（エラー扱いしない） |
| `gh` 未認証 | 「`gh auth login` を実行してください」と表示し該当 scope 終了 |
| リポジトリ 404 | 1 行警告で skip、他は続行（`gain-state record` は呼ばない） |
| RSS/changelog 取得失敗 | 当該ソースを skip、他は続行（`gain-state record` は findings=0 で呼ぶ） |
| SNS 取得ゼロ | 正常扱い（「該当なし」） |
| 全ソース取得失敗 | 「データを取得できませんでした」と報告し終了（ファイルは作らない） |
| deep-research 未利用可（research モード） | Web を内蔵 WebSearch で縮退実行し明示 |

## Red Flags（やってはいけないこと）

- watch の収集・ダイジェスト生成中にユーザーへ確認を求める（対話が要る事項は `## 改善提案` に書いて返すだけに留める）
- 教育解説で専門用語を読み手任せにする / 「自分の環境で何が変わるか」を省略する
- diff 判定を LLM 推測で行う（必ず grep/find/ls）
- サブエージェントの生出力を統合せずダイジェストへ転送する
- SNS を「信頼度低」ラベルなしで他ソースと同列に出す
- ユーザー承認なしに `sources.yaml` へアドホック対象を追記する
- `## 改善提案` の内容をこのスキル自身が `sources.yaml` に適用する（承認は呼び出し元が行う）
- distill-gain-latest-info が vault を自動 commit する（`/eod` に委譲）
