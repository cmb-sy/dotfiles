---
name: gain
description: >-
  技術情報を「集めて得る」ときに使う情報収集スキル。watch モード（GitHub /
  サービス changelog / エンジニア発信 / ニュース / dotfiles peer を横断観測し
  Obsidian にダイジェスト蓄積）と research モード（トピックを Web + 自リポジトリ
  横断で深掘り）を持つ。旧 peer-watch を吸収。フラグは本文の「起動」を参照。
argument-hint: "[watch|research|peers] [--only <scope>] [--target X] [--days N] [--dry-run]"
user-invocable: true
---

<!-- gain = "gather intel" + "得る(gain)". A portmanteau: gathering and obtaining tech intel. -->

# gain — 情報収集スキル

技術情報を集めて得るための単一スキル。2 モードを持つ。

- **watch（レーダー）**: `sources.yaml` を駆動し、前回以降の差分をダイジェスト化する
- **research（深掘り）**: トピックを Web 知見 × 自リポジトリ実態で調べる

**開始時アナウンス:** 「gain を開始します。」続けて選択されたモード/スコープを明示する。

## 起動

```
/gain                                   # 引数なし → 対話メニュー（デフォルト）
/gain watch                             # 全ウォッチを直接実行
/gain watch --only <scope> [--target X] # 単一スコープ、対象指定
/gain research <topic>                  # 深掘りを直接実行
/gain peers [--user <handle>] [--days N] [--dry-run]  # 旧 peer-watch 互換
```

- `<scope>`: `peers | github | services | engineers | sns | news`
- `engineers` は blog + SNS の両方、`sns` は engineers の SNS のみ
- `--days` は peers スコープの観測窓（default 30）
- `--dry-run` は peers スコープの採用対話・保存をスキップ

ARGUMENTS をパースし、第 1 引数（`watch`/`research`/`peers`）、`--only`、`--target`、`--days`、`--dry-run` を抽出する。第 1 引数が無ければ対話メニューへ。

## 対話フロー（引数なし起動時）

AskUserQuestion は 1 問最大 4 択のため 2 段構成にする。

**Q1「何をしますか?」**
1. 全ウォッチ（sources.yaml 全ソース）
2. ソースを選んで watch
3. research（深掘り調査）
4. dotfiles peer 観測（採用ワークフロー）

**Q2（Q1=2 のときのみ）「どのソース?」**
1. GitHub（一般リポジトリ）
2. SNS
3. changelog（サービス更新）
4. ニュース

- 単一スコープ / research を選んだら、続けて**対象を追加質問**する（例: SNS → 「誰の SNS?」を `sources.yaml` の登録者 + AI 推測候補 + 自由入力で提示）
- 選んだアドホック対象が `sources.yaml` に未登録なら、実行後に **「今後も watch 対象に追加しますか?」** を AskUserQuestion で確認 → YES で該当セクションに追記（単発 → 永続化）。ユーザー承認なしに追記しない

## watch: peers スコープ（dotfiles 採用ワークフロー）

旧 peer-watch の挙動を保持する。出力先は `dotfiles/docs/peer-watch/YYYY-MM-DD.md`（Obsidian ではない。採用対象が dotfiles 設定のため設定とバージョン管理を共にする）。

**基準日:** `dotfiles/docs/peer-watch/` の最新ファイルの `date` frontmatter を読み、その「後で」バケットを次回再提示候補として合流させる。

### Phase 1: Target Resolution
1. `--user <handle>` があればそれを単独対象。無ければ `sources.yaml` の `peers.handles` を対象化
2. repo 解決: `peers.overrides` に handle があればその `owner/name`、無ければ `<handle>/dotfiles`
3. `gh api /repos/{owner}/{name}` で存在検証。404 は 1 行警告で skip

### Phase 2: Activity Collection（並列）
1 peer = 1 サブエージェント（`subagent_type: general-purpose`、自己完結プロンプト）で並列 dispatch。各エージェントは直近 N 日（default 30）の以下を**構造化データ（YAML）**で返す:
- commit: `gh api '/repos/{owner}/{name}/commits?since=<iso8601>&per_page=100'` の message + changed files 要約
- 新規追加ファイル（commit 内 `status: added`）
- 注目ファイル（README.md / Brewfile / `*.json` / `*.yaml` / `flake.nix` / `chezmoi*.toml`）の更新有無
- star 数（`gh api /repos/{owner}/{name}` の `stargazers_count`）

返却スキーマ: `handle` / `repo` / `stars` / `last_commit` / `commits_in_window` / `themes[]`（`title`/`commits`/`files_touched`/`summary`）/ `notable_additions[]` / `notable_diffs[]`。

### Phase 3: Educational Analysis（メイン実行、subagent に投げない）
各 theme に以下 2 つを生成:
- **What（何をしているか）**: 2〜4 文。登場する専門用語は「そもそも何か」を 1〜2 文で必ず解説（省略禁止）
- **Why for me（自分への関係）**: `$HOME/dotfiles` を実 grep/find/ls で diff し（LLM 推測禁止）、ラベルを 1 つ付与:

| ラベル | 判定基準 |
|---|---|
| 🆕 NEW | 関連ファイルが見つからない |
| 🔁 OUTDATED | 同種はあるが古い/素朴 |
| ✅ COVERED | 同種があり自分が同等以上 |
| ❌ N/A | OS/流派/関心領域が異なる |

判定後、自分の運用への含意を 2〜3 文書く。

### Phase 4: Interactive Approval
`--dry-run` 時は Phase 4/5 をスキップ。finding を **1 件ずつ** AskUserQuestion で 4 択:
- 採用（memo に追記） / スキップ / 詳細を見る / 後で（次回再提示）

ルール: 一覧一括選択は禁止（1 件ずつ問う）。「詳細を見る」は commit diff・該当ファイル全体・自分の対応箇所を提示してから同 4 択を再提示（1 finding 1 回まで）。「採用」時にメモ 1 行を任意入力（空可）。

### Phase 5: Persistence
採用 finding と「後で」バケットを `dotfiles/docs/peer-watch/YYYY-MM-DD.md` に追記（無ければ作成、同日は追記）。frontmatter: `date` / `peers` / `days_window`。「後で」は次回 Phase 3 完了後に Read して再提示候補へ合流。

### 完了報告
```
gain peers 完了。対象: <n> peers (<days> 日窓)
finding: 採用 <a> / スキップ <b> / 後で <c>
記録先: dotfiles/docs/peer-watch/<date>.md
```

## watch: 一般ソース（github / services / engineers / news）

**基準日:** `02_skillup/情報収集/watch/` の最新ダイジェストの `date` を `since` とする。無ければ 14 日窓。

**実行:** スコープ内の各ソースカテゴリ = 1 サブエージェントで並列 dispatch（メイン context 保護）。各エージェントは自己完結プロンプトで**構造化データ**を返す。オーケストレーターが統合し、peers と同じ教育視点（What + 用語解説 + 自分への関係）でダイジェスト化する。サブエージェントの生出力をそのまま転送しない。

| スコープ | 取得方法 | 信頼度 |
|---|---|---|
| github | `gh api /repos/{repo}/commits?since=<iso>` + `/releases`。「何を作っているか」を要約 | 高 |
| services | changelog URL を WebFetch → 基準日以降のエントリ抽出（前回ダイジェストと照合し重複除去） | 中〜高 |
| engineers(blog) | RSS/Atom を WebFetch → 基準日以降の記事。RSS 無しは WebFetch スクレイプにフォールバック | 高 |
| engineers(sns) | WebSearch で直近の注目投稿（threadreader/引用/埋め込み経由） | **低（best-effort）** |
| news | クエリごとに WebSearch → 影響度・新しさでフィルタ | 中 |

SNS は必ず「信頼度低」ラベルを付す。取得ゼロは正常扱い（「該当なし」と記載）。

## research モード

トピックを受け取り並列で:
- **Web**: 既存 `deep-research` スキルを invoke（fan-out 検索 + adversarial verify + 出典付き）。利用不可なら内蔵 WebSearch で縮退し、その旨を明示
- **自リポ**: `code-explorer` 系サブエージェントで現リポジトリの関連構造・依存・既存実装を調査

オーケストレーターが両者を統合:
- 技術選定 → 導入可否・影響範囲・既存コードとの整合性
- 外部リポ理解 → 設計/実装の要約 + 自リポへの取り込みポイント

出力: `02_skillup/情報収集/research/YYYY-MM-DD-<topic>.md`

## 出力構造（Obsidian）

```
02_skillup/情報収集/
├── watch/YYYY-MM-DD.md          # 実行ごとのダイジェスト
├── research/YYYY-MM-DD-<topic>.md
└── index.md                     # MOC: 直近ファイルへのリンク一覧
```

ダイジェスト md:
```markdown
---
date: YYYY-MM-DD
type: watch-digest
tags: [情報収集, tech-radar]
---
# 情報収集ダイジェスト YYYY-MM-DD

## GitHub
### owner/repo — <テーマ>
- 何をしているか: ...
- 自分への関係: ...
- source: <URL>

## サービス更新
## エンジニア発信（blog / SNS·信頼度低）
## ニュース
```

- `[[]]` リンク・`#tag` を維持。実行後 `index.md` に新ファイルへのリンクを追記
- vault の commit/push はしない（/eod に委譲）

## エラーハンドリング

| 状況 | 対応 |
|---|---|
| `gh` 未認証 | 「`gh auth login` を実行してください」と表示し該当スコープ終了 |
| リポジトリ 404 | 1 行警告で skip、他は続行 |
| RSS/changelog 取得失敗 | 当該ソースを skip、他は続行 |
| SNS 取得ゼロ | 正常扱い（「該当なし」） |
| 全ソース取得失敗 | 「データを取得できませんでした」と報告し終了 |
| deep-research 未利用可 | Web を内蔵 WebSearch で縮退実行し明示 |

## Red Flags（やってはいけないこと）

- peers で finding を一覧一括選択させる（1 件ずつが要件）
- 教育解説で専門用語を読み手任せにする / 関連性ラベルを省略する
- diff 判定を LLM 推測で行う（必ず grep/find/ls）
- サブエージェントの生出力を統合せずダイジェストへ転送する
- SNS を「信頼度低」ラベルなしで他ソースと同列に出す
- ユーザー承認なしに sources.yaml へアドホック対象を追記する
- gain が vault を自動 commit する（/eod に委譲）
