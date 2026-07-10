---
name: peer-watch
description: >-
  他メンテナーの dotfiles リポジトリの直近の動きを観測して自分の設定に取り入れたいときに使う。
  各 finding を教育プロ視点で「何をしているか」「自分にどう関係するか」を関連性ラベル付きで解説し、
  採用/スキップ/詳細/後で を 1 件ずつ対話選択して採用分を記録する。オプションは本文の「起動」を参照。
argument-hint: "[--user <handle>] [--days N] [--dry-run]"
user-invocable: true
---

# Peer Watch — dotfiles 同業者の動向観測ワークフロー

GitHub の他メンテナーの dotfiles リポジトリの最近の活動を観測し、**教育のプロフェッショナル**として「何をしているか」「自分にどう関係するか」を解説する。finding ごとに採否を 4 択で対話的に決め、採用された内容は永続化する。

**開始時アナウンス:** 「Peer Watch を開始します。Phase 1: Target Resolution」

## 起動

```
/peer-watch                              # peers.yaml の全員、過去 30 日
/peer-watch --user mizchi                # 1 人だけ、過去 30 日
/peer-watch --days 14                    # 過去 14 日
/peer-watch --user shunk031 --days 7     # 組み合わせ
/peer-watch --dry-run                    # Phase 3 まで実行、Phase 4 の対話と Phase 5 の保存は省略
```

ARGUMENTS をパースし、`--user`, `--days` (default: 30), `--dry-run` を抽出する。

## Phase 1: Target Resolution

**アナウンス:** 「Phase 1: Target Resolution — 監視対象を確定します」

### 動作

1. `--user <handle>` が指定されていればそれを単独対象とする
2. 指定がなければ `claude/skills-src/ops/peer-watch/peers.yaml` を Read で読み込み、`peers:` のリストを対象とする
3. 各 handle について、リポジトリ URL を解決する:
   - `overrides:` に handle のエントリがあればその値（`owner/name`）を採用
   - なければデフォルト `<handle>/dotfiles` を採用
4. 各リポジトリの存在を `gh api /repos/{owner}/{name}` で軽く検証する。404 ならその handle を skip し、警告を 1 行出す

### 出力（標準出力に短く）

```
Target: 5 peers (default list, days=30)
  - neko-neko    → neko-neko/dotfiles
  - mizchi       → mizchi/chezmoi-dotfiles  [override]
  - joshukraine  → joshukraine/dotfiles
  - shunk031     → shunk031/dotfiles
  - yutkat       → yutkat/dotfiles
```

## Phase 2: Activity Collection (並列)

**アナウンス:** 「Phase 2: Activity Collection — 各リポジトリの活動を並列取得します」

各 peer につき以下を取得する。**サブエージェントを 1 peer = 1 agent で並列 dispatch** すること（メインの context を消費せず、重い API 取得を並列化する）。

### 各サブエージェントへの指示

`subagent_type: general-purpose`、プロンプトは自己完結で以下を含める:

- peer の handle と repo (`owner/name`)
- 取得対象:
  - 直近 N 日のコミット: `gh api '/repos/{owner}/{name}/commits?since=<iso8601>&per_page=100'` で取得し、各 commit の message と changed files を要約
  - 新規追加ファイル: コミット内の `status: added` を抽出
  - 注目ファイル (README.md / Brewfile / `*.json` / `*.yaml` / `flake.nix` / `chezmoi*.toml` 等) の更新有無
  - star 数の現状（`gh api /repos/{owner}/{name}` の `stargazers_count`）
- 出力形式（**重要：人間向けの装飾ではなく構造化データを返す**）:

```yaml
handle: <handle>
repo: <owner/name>
stars: <int>
last_commit: <ISO8601>
commits_in_window: <int>
themes:
  - title: <短い見出し、例: "sesh + zoxide 統合">
    commits: [<sha-7>, <sha-7>, ...]
    files_touched: [<path>, <path>, ...]
    summary: <2-3 文の要約>
  - ...
notable_additions:
  - path: <new file path>
    purpose: <その file が何のためか、1 文>
notable_diffs:
  - file: README.md
    change_summary: <1 文>
```

メイン側はこの YAML を merge してから Phase 3 に進む。

## Phase 3: Educational Analysis (教育プロ視点)

**アナウンス:** 「Phase 3: Educational Analysis — 各テーマを解説し、自分との関連を判定します」

ここはメインエージェントが直接実行する（subagent に投げない。教育的解説の質を担保するため）。

各 peer の各 theme について、以下 2 つを生成する:

### What (何をしているか)

- 2〜4 文で、その theme で起きていることを説明
- **必ず**：登場した専門用語（ツール名・概念・パターン名）のうち、ユーザーが知らない可能性のあるものを **「そもそも何か」から 1〜2 文で解説**
  - 例: 「chezmoi: dotfiles 管理ツール。`~/` 配下のファイルを git 管理可能な形に抽象化し、マシン固有値や暗号化を扱える」
  - 例: 「sesh: tmux セッションを `fzf` で選ぶランチャ。プロジェクトディレクトリから自動でセッション名を推測する」
- 用語が複数あれば全て解説する。「読者は知ってる前提」で省略しない

### Why for me (自分にどう関係するか)

ユーザーの dotfiles (`$HOME/dotfiles`) と実際に diff を取り、以下のラベルから 1 つを付ける:

| ラベル | 意味 | 判定基準 |
|---|---|---|
| 🆕 NEW | 自分にない、取り入れる価値あり | grep / find で関連ファイルが見つからない |
| 🔁 OUTDATED | 自分にもあるが、彼らの方が新しい / 洗練されている | 同種のファイルはあるが、内容が古い・素朴 |
| ✅ COVERED | 自分にもあって同等以上 | 同種のファイルがあり、自分の実装が同等以上 |
| ❌ N/A | 自分には不要 | OS が違う、流派が違う、関心領域外 |

判定後、ユーザー自身の運用に対する具体的な含意を 2〜3 文で書く（「これを取り入れると ○○ が改善される」「すでに △△ で同等のことができている」）。

### 1 finding の出力形式（チャットに出す）

```
─────────────────────────────────────────────────────
[peer] mizchi   [theme] pkfire + secretlint pre-push gate
─────────────────────────────────────────────────────
What:
  pkfire は pre-push hook を nix-darwin overlay で home-manager に統合する
  自作ツール (mizchi 製)。pre-push hook は git push 直前に走るスクリプトで、
  CI に出す前にローカルで最終チェックする層。secretlint は API キーや
  password のような機密情報がコミットに含まれていないかを正規表現で検知
  する Linter。両者の組み合わせで「push する前に必ずシークレットスキャン」
  が強制される。

Why for me [🆕 NEW]:
  あなたの dotfiles には git hooks 関連のファイルが見当たらず (確認: ls
  -la $HOME/dotfiles/.git/hooks)、CLAUDE.md の PII Protection
  憲法に対応する未実装の防御層がある。secretlint 自体はインストール不要で、
  npm 経由で 1 コマンド導入可能。pre-push に組み込めば、Slack や Linear に
  PII を送る前の最後のセーフティネットになる。

Source:
  - https://github.com/mizchi/chezmoi-dotfiles/blob/main/...
  - 直近 commit: <sha> "feat: pkfire integration"
```

## Phase 4: Interactive Approval

**アナウンス:** 「Phase 4: Approval — 各 finding について採否を選択してください」

`--dry-run` 指定時は Phase 4 と Phase 5 をスキップして終了。

各 finding を Phase 3 の形式で **1 つずつ** 提示し、AskUserQuestion で以下の 4 択を出す:

```
Q: この finding をどうしますか？
A:
  - 採用 (memo に追記)
  - スキップ (今は不要)
  - 詳細を見る (commit 内容・該当ファイル・周辺コード)
  - 後で (later バケットに記録、次回再提示)
```

**重要なルール:**

- **finding を 1 度に複数まとめて選ばせない**。1 つずつ「やりますか？」を問う
- 「詳細を見る」が選ばれたら、関連 commit の diff・該当ファイル全体・自分の dotfiles の対応箇所を提示してから、同じ 4 択を再度出す（無限ループ防止：「詳細」は 1 finding につき 1 回まで）
- 「採用」が選ばれた場合、その場で 1 行の「自分のメモ」を AskUserQuestion で任意入力させる（空でも可）

## Phase 5: Persistence

**アナウンス:** 「Phase 5: Persistence — 採用された finding を記録します」

採用された finding と「後で」バケットを以下に追記する:

- 出力先: `$HOME/dotfiles/docs/peer-watch/YYYY-MM-DD.md`
- ディレクトリが無ければ作成
- 既存ファイルがあれば追記（同日複数回実行を想定）

### ファイル形式

```markdown
---
date: 2026-06-21
peers: [neko-neko, mizchi, joshukraine, shunk031, yutkat]
days_window: 30
---

# Peer Watch — 2026-06-21

## 採用 findings

### 1. [mizchi] pkfire + secretlint pre-push gate  [🆕 NEW]

**What**: pkfire は pre-push hook を nix-darwin overlay で... (Phase 3 の What 全文)

**Why for me**: あなたの dotfiles には git hooks 関連が... (Phase 3 の Why 全文)

**Source**:
- https://github.com/mizchi/chezmoi-dotfiles/blob/main/...
- 直近 commit: <sha> "feat: pkfire integration"

**自分のメモ**: <ユーザーが Phase 4 で入力した 1 行、空なら省略>

### 2. ...

## 後で バケット

### 1. [yutkat] firejail + npm proxy サンドボックス  [🆕 NEW]
（次回 /peer-watch 実行時に再提示）

...
```

### 完了時アナウンス

```
Peer Watch 完了。
  対象: 5 peers (30 日窓)
  finding 総数: <int>
  採用: <int> / スキップ: <int> / 後で: <int>
  記録先: docs/peer-watch/2026-06-21.md
```

## 設計上の注意

### 「後で」バケットの永続化

「後で」と判定された finding は、次回 `/peer-watch` 実行時に **新規 finding と合わせて再提示** する。実装は: Phase 5 で保存した最新の `docs/peer-watch/*.md` を Phase 3 完了後に Read し、「後で」セクションの finding を「再提示候補」として finding リストに合流させる。

### diff 判定の grep ベース実装

「自分にどう関係するか」を判定するために、`$HOME/dotfiles` を grep / find / ls で実際に探索する。**LLM の推測で「ありそう/なさそう」を判定しない**。grep で見つからなければ 🆕、見つかれば内容を読んで 🔁 / ✅ を判定する。

### 教育解説の深さ

専門用語を解説する範囲は **「ユーザーがその語を見て即座にイメージできるか」** で判断する。判断に迷ったら解説を入れる側に倒す（過剰でも害は少ないが、未解説で読み手が止まるのは害が大きい）。CLAUDE.md の「技術メモ」のような厚みは必須ではないが、最低 1 文の定義は必ず添える。

## やってはいけないこと

- ❌ Phase 4 で finding を一覧表示して「全部採用/全部スキップ」を聞く（1 つずつ問う設計が user 要件）
- ❌ Phase 3 で「専門用語の解説は読み手任せ」にする（教育プロ視点が要件）
- ❌ Phase 3 で関連性ラベルを省略する（4 ラベルは必須）
- ❌ Phase 2 を直列で順に取得する（並列 dispatch が要件、5 peer ✕ 数秒 = 重い）
- ❌ peers.yaml の handle に override で repo 名を「念のため」全部書く（命名規約に従う handle は handle だけで十分）

## 失敗時の挙動

- リポジトリが 404: 警告 1 行を出して当該 peer を skip、他は続行
- `gh` コマンドが未認証: 「`gh auth login` を実行してください」と表示して終了
- 全 peer で取得失敗: Phase 2 終了時に「データを取得できませんでした」と報告して終了
