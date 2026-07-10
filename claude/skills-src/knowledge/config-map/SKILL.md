---
name: config-map
description: private/work アカウント間で Claude Code 設定の差分を確認したいときに使う。settings.json・CLAUDE.md・hooks・skills/agents・MCP コネクタを一覧化し、共通ブロックと差分対比表で可視化する。差分のみの表示は argument-hint を参照。
argument-hint: "[--diff-only]"
user-invocable: true
---

現在の Claude Code 設定を一覧化し、private/work アカウント間の差分を可視化する。

**モード:**
- **引数なし**: 共通設定ブロック + アカウント差分対比表の両方を表示
- **`--diff-only`**: アカウント差分対比表のみ表示

---

## 前提: 2アカウント構成の仕組み

`.aliases.sh` の `CLAUDE_ACCOUNT_PRIVATE_DIR` (既定 `~/.claude-private`) と
`CLAUDE_ACCOUNT_WORK_DIR` (既定 `~/.claude-work`) がそれぞれ独立した
`CLAUDE_CONFIG_DIR`。`claude/link-shared-config.zsh` が
`settings.json` / `hooks` / `statusline.sh` / `skills` / `agents` / `CLAUDE.md`
をこの dotfiles リポジトリから両方のアカウントディレクトリへ symlink するため、
これらは **原理的に常に同一**。差分が生まれるのは symlink されない
アカウント固有のローカル状態(ログイン情報、`settings.local.json`、
実際に接続済みの MCP コネクタ、`.aliases.sh` が起動時に付与するデフォルト
フラグ)だけである。この前提を裏切る値を見つけたら(例: 本来共通のはずの
ファイルが symlink になっていない)、正常でない設定ドリフトとして明示する。

---

## 処理フロー

### Step 1: 共通設定の収集(dotfiles配下、両アカウントに symlink される実体)

- `{DOTFILES:-~/dotfiles}/claude/settings.json` を Read し、以下を抽出:
  - `env` の全キー
  - `hooks` の各イベント(PreToolUse/PostToolUse/SessionStart等)ごとの matcher + command
  - `enabledPlugins` の全リスト
  - `statusLine.command`
  - `permissions`(存在すれば)
- `{DOTFILES}/claude/CLAUDE.md` を Read し、`^# ` / `^## ` の見出し行だけ抽出して
  構成の目次を作る(全文は表示しない。長すぎるため)
- `{DOTFILES}/claude/skills/` を走査し、symlink先のカテゴリディレクトリ
  (`skills-src/<category>/`)からカテゴリ別スキル数を集計する。個々のスキルの
  詳細な依存関係は重複させず「詳細は /skills-map 参照」とだけ添える
- `{DOTFILES}/claude/agents/*.md` を走査し、各ファイルの frontmatter
  `description`(またはファイル先頭の説明)を1行ずつ抽出する。
  `description: >-` や `description: |` のようなYAML複数行ブロック記法の
  場合、値は次の行以降に続く。`grep -m1 '^description:'` だけでは中身が
  空 (`>-`) に見えるので、その場合は直後の行(インデントされた本文)も
  合わせて Read すること

### Step 2: アカウント別ローカル状態の収集(symlinkされない実体)

`.aliases.sh` から `CLAUDE_ACCOUNT_PRIVATE_DIR` / `CLAUDE_ACCOUNT_WORK_DIR` の
実際の値と、`CLAUDE_PRIVATE_DEFAULT_EFFORT` / `CLAUDE_PRIVATE_DEFAULT_MODEL` /
`CLAUDE_WORK_DEFAULT_EFFORT` / `CLAUDE_WORK_DEFAULT_MODEL` の現在値
(未設定なら `.aliases.sh` 内の `:=` デフォルト値)を読み取る。

各アカウントディレクトリに対して:
- `[ -f "$ACCOUNT_DIR/settings.local.json" ]` — 存在すれば中身を Read (permissions
  overrideなど、dotfiles管理外のローカル設定)
- `CLAUDE_CONFIG_DIR="$ACCOUNT_DIR" claude mcp list` を実行し、サーバーごとの
  接続状態を取得する。**settings.json の enabledPlugins は共通でも、実際の
  MCP接続状態(ログイン/OAuth次第)はアカウントごとに異なりうる** ため、
  静的な設定ファイルだけでなく必ずこのコマンドで実測すること
- `[ -L "$ACCOUNT_DIR/settings.json" ]` 等で主要ファイルが正しく symlink に
  なっているかを確認する(なっていなければ設定ドリフトとして警告)

usage 履歴・セッション状態(`stats.db`, `telemetry/`, `projects/`, `sessions/`,
`.claude.json` の中身等)は「設定」ではないため対象外。ログイン有無の事実
(どちらもログイン済みか)だけ触れてよい。

### Step 3: 出力

出力はプレーンテキスト + ASCII のみ。特殊文字・絵文字は使わない
(skills-map と同じ規約)。

---

#### 引数なしの出力フォーマット

**ブロック1: 共通設定(private/workで完全に同一)**

```
+-----------------------------------------------------------+
|  CLAUDE CONFIG MAP        shared (symlink元: dotfiles/claude/)  |
+-----------------------------------------------------------+

  env:            CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1, ENABLE_TOOL_SEARCH=true, ...
  hooks:
    SessionStart  -> session-start.sh, herdr-agent-state.sh
    PreToolUse    -> (matcher: Write) ...
    PostToolUse   -> (matcher: Bash) post-commit.sh
  enabledPlugins: ast-grep, claude-md-management, code-simplifier, codex, ...(N件)
  statusLine:     ~/.claude/statusline.sh

  CLAUDE.md 見出し:
    # 役割定義 / コミュニケーション方針 / 言語 / ... (全N見出し)

  skills: 開発フロー(N) コードレビュー(N) ドキュメント(N) ... 合計N件
    (詳細は /skills-map を参照)
  agents: N件
    code-review-security | セキュリティとデータ安全性をレビュー...
    ...
```

**ブロック2: アカウント差分対比表**

```
DIFF: private vs work  (symlinkされないローカル状態のみ)
------------------------------------------------------------
                        private                  work
CLAUDE_CONFIG_DIR       ~/.claude-private         ~/.claude-work
起動デフォルト effort    medium (clp/clpa)         xhigh (clw/clwa)
起動デフォルト model     (未設定)                   (未設定)
settings.local.json     permissions.allow:        (なし)
                          Bash(nvim:*)
MCP接続状態(実測)        plugin:playwright ok      plugin:playwright ok
                        plugin:linear 未認証        plugin:linear 未認証
                        plugin:context7 --         plugin:context7 ok
                        claude.ai系コネクタ N件 共通
ログイン                済み                       済み
------------------------------------------------------------
* settings.json / CLAUDE.md / hooks / skills / agents / statusline.sh は
  dotfilesからのsymlinkのため上記に含めない(ブロック1で共通表示済み)。
* 上記の実際の値は都度 claude mcp list 等で実測すること。ここに書いた値は
  出力フォーマットの例であり、ハードコードしてはならない。
```

---

#### `--diff-only` の出力フォーマット

ブロック2(アカウント差分対比表)のみを表示する。

---

## ルール

1. 値は必ずライブで取得する(このファイルに書かれた例の値をそのまま出力しない)
2. `claude mcp list` は private/work 両方で実行し、実測の差分のみを載せる
   (enabledPlugins の静的リストだけで「差がある」と決めつけない)
3. symlink されて共通のはずのファイルが实際に symlink になっていない場合は
   「設定ドリフト」として明示的に警告する
4. usage 履歴・キャッシュ・セッション状態など「設定」でないものは対象外
5. 出力はプレーンテキスト + ASCII のみ。絵文字・装飾記号は使わない
6. CLAUDE.md は見出し一覧のみ(全文コピーは禁止。長すぎる)
7. skills の詳細は重複させず /skills-map を参照するよう促す
