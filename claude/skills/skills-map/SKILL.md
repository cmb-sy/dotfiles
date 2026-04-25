---
name: skills-map
argument-hint: "[--category <カテゴリ名>] [--deps] [--search <キーワード>]"
---

保持しているスキルをカテゴリー別・依存関係付きで一覧表示する。

**モード:**
- **引数なし**: カテゴリーグリッド + 依存ツリー + スキル詳細を表示
- **`--category <名前>`**: 指定カテゴリのスキルのみ詳細表示（部分一致）
- **`--deps`**: 依存関係ツリーのみ表示
- **`--search <キーワード>`**: キーワードに部分一致するスキルを横断検索

---

## 処理フロー

### Step 1: スキルの収集

以下を並列で走査しスキル定義ファイルを収集する。

- `~/.claude/skills/` — グローバル（dotfiles）。各サブディレクトリの `SKILL.md` を対象とする
- `{current_project}/.claude/skills/` — プロジェクト固有の `SKILL.md`（存在すれば）
- `{current_project}/.claude/commands/` — プロジェクト固有の旧形式コマンド（`.md`）。`skills/` と重複する name は `skills/` を優先する

各 SKILL.md から抽出:
- frontmatter の `name` / `argument-hint`
- frontmatter 直後の最初の非空行（1行説明）
- `--` フラグ一覧
- 他スキル名への言及（依存関係）

### Step 2: 出力

出力はプレーンテキスト + ASCII のみ。特殊文字・絵文字禁止。

---

#### 引数なしの出力フォーマット

**ブロック1: カテゴリーグリッド（全体を一目で把握）**

```
+-----------------------------------------------------------+
|  CLAUDE SKILLS MAP   global:N  project:M  total:N+M      |
+-----------------------------------------------------------+

  [開発フロー    ]  feature-dev / debug-flow / tdd-orchestrate / smoke-test
  [コードレビュー]  code-review / test-review / spec-review / implementation-review
  [ドキュメント  ]  doc-audit / doc-check / learn / handover / continue
  [PJ管理       ]  linear-refresh / github-ops / triage / project-update
  [振り返り・成長]  reflect / reflect-review
  [外部ツール    ]  slackcli / trace-report / skills-map
  [Obsidian固有  ]  daily-log / eod  (*reflect *reflect-review *project-update は共有)

  * = グローバルと同名のプロジェクト版。Obsidian パスに特化。
```

**ブロック2: 依存ツリー（呼び出し関係を視覚化）**

```
DEPENDENCY TREE  (A -> B : AがBを呼び出す)
------------------------------------------

  feature-dev ----+-> spec-review
                  +-> implementation-review
                  +-> code-review
                  +-> test-review
                  +-> smoke-test
                  +-> doc-audit
                  +-> doc-check
                  +-> learn

  debug-flow -----+-> code-review
                  +-> test-review
                  +-> smoke-test

  eod +-----------+-> linear-refresh --+-> slackcli
      |                                +-> project-update -> slackcli
      +-> daily-log -----------------> slackcli
      +-> project-update

  reflect-review -> reflect_log.md (file read)
  continue       -> handover.md    (file read)
```

**ブロック3: スキル詳細（カテゴリー別、コンパクト）**

1スキルあたり最大4行に収める。フォーマット:

```
  skill-name      [flags]
  | 説明1行
  | 使いどき: ...
```

全カテゴリー分を順番に表示する。

---

#### `--deps` の出力フォーマット

依存ツリーのみ拡張版で表示する。各ノードに簡単な説明を付与する。

```
DEPENDENCY TREE (拡張版)
------------------------------------------

  [開発フロー]

    feature-dev (10フェーズ開発)
      +-> spec-review         (設計書レビュー 4観点)
      +-> implementation-review (計画書レビュー 3観点)
      +-> code-review         (コードレビュー 6観点)
      |     +-> (並列サブエージェント)
      +-> test-review         (テストレビュー 3観点)
      |     +-> (並列サブエージェント)
      +-> smoke-test          (動作確認・VRT・E2E)
      |     +-> code-review
      |     +-> test-review
      +-> doc-audit           (ドキュメント監査)
      |     +-> doc-check
      +-> doc-check           (変更影響ドキュメント更新)
      +-> learn               (学習教材生成)

    debug-flow (8フェーズデバッグ)
      +-> code-review
      +-> test-review
      +-> smoke-test

  [Obsidianワークフロー]

    eod (1コマンド締め)
      +-> linear-refresh (チケット棚卸し)
      |     +-> slackcli
      |     +-> project-update
      |           +-> slackcli
      +-> daily-log (日報集約)
      |     +-> slackcli
      +-> project-update

  [セッション継続]

    handover (要約生成)
      <-- continue (読み取り・再開)
```

---

#### `--category <名前>` の出力フォーマット

指定カテゴリのスキルのみ、詳細フォーマットで表示する。

```
  skill-name      [flags]
  | 説明
  | 使いどき: ...
  | 呼び出し: A -> B -> C
  | 参考: /skill-name --flag で起動
```

---

#### `--search <キーワード>` の出力フォーマット

```
"<キーワード>" の検索結果:
  linear-refresh  -- 直接一致: Linearチケット棚卸し
  triage          -- 含む: Linear Issue 登録を実行
  eod             -- 呼び出し: linear-refresh を invoke
  daily-log       -- フラグ: --linear-refresh を持つ
```

---

## ルール

1. SKILL.md を実際に Read してから表示する（ハードコード禁止）
2. 出力はプレーンテキスト + ASCII のみ。特殊文字・絵文字・装飾記号は使わない
3. 1スキルあたりの説明は最大4行。冗長な文は削る
4. プロジェクト固有スキルはグローバルと明示的に区別して表示する
5. 新スキルが追加されてもディレクトリ走査で自動反映する
