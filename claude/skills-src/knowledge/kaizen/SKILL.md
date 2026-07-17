---
name: kaizen
description: >-
  誤解・修正・ハルシネーションが起きたセッションを振り返り、再発防止まで落とし込みたい
  ときに使う。1 回の実行で 4 視点（ハルシネーション予防 / ユーザー指示の改善 /
  CLAUDE.md・settings.json の進化 / スキル提案）を並列分析する継続改善ループ。
argument-hint: "[--transcript PATH] [--apply] [--no-user-side] [--limit N]"
user-invocable: true
---

# Kaizen

Claude Code セッションを 4 視点で振り返り、ハルシネーション予防 / ユーザースキルアップ / Claude 設定の進化 / スキル提案を一気通貫で実行する継続改善ループスキル。

**開始時アナウンス:** 「Kaizen を開始します。Phase 1: Scope」

## 役割定義

あなたはセッション分析の独立監査人として、Claude とユーザー双方の改善点を**忖度なく**指摘する責任を負う。褒める係ではない。

### 反 sycophancy ハードルール（最重要）

このスキルが機能不全に陥る最大のリスクは「全体的に良かった」と褒めること。以下を厳守:

- **「特に問題なし」報告を禁止**: 4 視点それぞれで最低 1 件は指摘する。重大な指摘がなければ「軽微」レベルで 1 件出す
- **抽象的な対策を禁止**: 「気をつける」「丁寧に対応する」「より注意する」「明示的に伝える」は禁止語彙。具体的に何をどう変えるかを書く
- **transcript 直接引用を伴う**: 全 finding に「あの発言・あの編集」レベルの引用を含める。要約だけでは不可
- **ユーザー側の指摘を遠慮しない**: プロの目線でユーザーの曖昧指示・誤前提・指示混在を率直に書く。「ユーザーは悪くない」式の擁護をしない
- **「次回気をつけます」式の謝罪を書かない**: 行動変容の記述のみ

### 4 視点（並列分析、各最低 1 件）

| 視点 | 検出対象 | 必須出力 |
|---|---|---|
| **Hallucination** | 存在しない API / フラグ / ファイル / コマンドへの言及、推測の断定、誤った事実、未確認の前提 | 引用 + 根本原因（Claude / User / 環境） + 防止ルール |
| **User Skill** | 曖昧指示、必要文脈の省略、誤前提、指示混在、技術用語の誤用 | 引用 + 「次回こう書く」before/after 例 |
| **Config Evolution** | CLAUDE.md 追加ルール、settings.json / hooks で機械的予防可能な事項 | 実 diff 案（適用可能形式） |
| **Skill Proposals** | 既存スキルの未活用、新規スキル化推奨パターン | 既存: `/skill-name ARGS` 形式 / 新規: name + description 草案 + 想定フェーズ |

### 禁止事項

- 過去の `learning-log.md` と同じ指摘を新規 finding として再掲しない（「N 回目」とマークして強調）
- 「特に問題なし」「順調」「良いセッション」等のポジティブ評価を出さない
- 視点を「該当なし」でスキップしない
- LLM の知識で「一般論として〜」と語らない。transcript 内の事象のみ扱う

## ワークフロー

| # | Phase | 監査 |
|---|---|---|
| 1 | Scope（transcript path 特定、対象範囲確定） | lite |
| 2 | Collect（transcript + global/project CLAUDE.md + settings.json + 既存 skill 一覧 + learning-log 履歴） | — |
| 3 | Analyze 4 視点並列（subagent 4 体） | **required** |
| 4 | Synthesize（重複統合、過去ログと突合して繰り返し検出） | — |
| 5 | Propose & Apply（diff 提示、ユーザー承認後に CLAUDE.md / settings.json を実書換） | lite |

セッション成果物: `~/.kaizen/sessions/<YYYY-MM-DD-HHMM>/`
累積ログ: `~/.kaizen/learning-log.md`

---

## Phase 1: Scope

`--transcript PATH` 指定が無ければ、**直近の transcript** を自動特定:

1. `find ~/.claude/projects -name "*.jsonl" -newer /tmp/kaizen-marker` で対象を取得
2. 最終更新が最新の .jsonl を採用（= 現在進行中のセッション）
3. パスをユーザーに提示して確認

`--limit N` で直近 N ターンに限定可能（デフォルトは全範囲）。

監査（lite）: transcript ファイルが存在し読み取り可能であること。

---

## Phase 2: Collect

並列で読み込む:
1. transcript（jsonl をパースして user / assistant メッセージのペアを抽出）
2. global CLAUDE.md（`~/.claude/CLAUDE.md` または `~/.claude-work/CLAUDE.md`）
3. project CLAUDE.md（cwd から探索）
4. settings.json（global + project）
5. 既存 skill 一覧（`claude/skills/*/SKILL.md` の frontmatter）
6. learning-log（`~/.kaizen/learning-log.md` の過去 finding）

---

## Phase 3: Analyze（**audit: required**）

4 視点を **subagent 4 体並列** でレビュー。各 subagent には:
- transcript 全文
- 該当する参照ファイル（CLAUDE.md / settings.json / skill 一覧）
- 反 sycophancy ハードルールを必ず伴うシステムプロンプト
- 「最低 1 件は出力する」明示

### 視点 1: Hallucination

**検出対象**:
- 存在しないコマンド / フラグ / API / ファイルパスへの言及
- 「〜があります」と断定したが実際は無かった事象
- 未確認の前提（ツール存在、ファイル存在、状態）
- 推測ベースの数値・データ

**出力形式**:
```markdown
**H1 [severity]**: <一行サマリ>
- 引用: "<transcript からの直接引用>"
- 実際: <現実との差分>
- 根本原因: Claude 側 / User 側 / 環境（MCP 切断等）
- 防止: <具体的な行動変容>
```

### 視点 2: User Skill

**検出対象**:
- 曖昧な代名詞（「あれ」「それ」）の単独使用
- 1 メッセージに複数タスクが番号付けなく混在
- 必要な前提（ファイルパス、目的、制約）の省略
- 誤った前提（存在しないものを既存と仮定）
- 「もどして」「進めて」など差分情報なしの差分指示

**出力形式**:
```markdown
**U1 [severity]**: <一行サマリ>
- 引用: "<transcript からの直接引用>"
- 問題: <何が曖昧 / 不足 / 誤っているか>
- 次回こう書く:
  - Before: "<元の指示>"
  - After: "<改善版>"
```

### 視点 3: Config Evolution

**検出対象**:
- CLAUDE.md に追加すべきルール（複数セッションで再発する Claude 失敗）
- settings.json / hooks で機械的に予防可能な事項（permission 追加、PreToolUse hook）
- 既存ルールの曖昧さ・矛盾

**出力形式**:
```markdown
**C1 [severity]**: <一行サマリ>
- 引用: "<関連発話・編集>"
- 提案: <ファイル名>
- diff:
  ```diff
  - <削除行>
  + <追加行>
  ```
- 効果: <この変更で何が予防されるか>
```

### 視点 4: Skill Proposals

**検出対象**:
- 今セッションで手動で実施した、3 ステップ以上の手続き的作業
- 既存 skill の description と類似する未使用 skill
- 同じパターンが過去ログに 2 回以上記録あり = skill 化推奨

**出力形式**:
```markdown
**S1 [severity] [A|B|C]**: <一行サマリ>
- 引用: "<該当作業の transcript 引用>"
- 分類:
  - A. 既存スキル該当: `/skill-name ARGS` で実行可能
  - B. 新規スキル化推奨:
    - name: <kebab-case 名>
    - description: "Use when ..."
    - 想定フェーズ: <3〜5 フェーズの簡潔リスト>
  - C. skill 化不要（単発のみ・特殊ケース）
```

### 監査（required）

`done-criteria/analyze.md` で検証:
- 4 視点全てに最低 1 件
- 全 finding に transcript 引用が存在（要約は不可）
- 全 finding に具体的アクションが存在（禁止語彙不使用）
- 既存 learning-log の重複 finding は「N 回目」とマーク済み

---

## Phase 4: Synthesize

1. 4 視点の出力を統合
2. 過去 learning-log と突合し、繰り返し finding は冒頭に「⚠ 再発 N 回目」を付加
3. severity でソート（high → medium → low）

`~/.kaizen/sessions/<YYYY-MM-DD-HHMM>/report.md` に保存。

---

## Phase 5: Propose & Apply

ユーザーに以下を提示:

```markdown
## Kaizen 適用提案

### 自動適用候補
- CLAUDE.md 編集: [C1] [C2]
- settings.json 編集: [C3]

### 別途実行が必要
- 新規 skill 作成: [S1] → `/superpowers:writing-skills` で TDD 作成
- 既存 skill 試用: [S2] → 次回 `/github-issues pr` を使う

適用しますか? (y / N / 部分選択)
```

承認後:
- CLAUDE.md / settings.json を実 diff で書き換え
- `learning-log.md` に今回 finding を全件追記（後の再発検出用）
- 新規 skill 作成は `/superpowers:writing-skills` 起動を案内（自動起動はしない）

---

## 完了報告

```
## kaizen 完了

対象 transcript: <path>
範囲: <N ターン>

検出 findings:
  Hallucination: A 件（H1〜HA）
  User Skill: B 件
  Config Evolution: C 件
  Skill Proposals: D 件
  ⚠ 過去再発: E 件

適用:
  CLAUDE.md: F 箇所更新
  settings.json: G 箇所更新
  skill 作成案内: H 件

セッション成果物: ~/.kaizen/sessions/<...>/
累積ログ更新: ~/.kaizen/learning-log.md (line 追加 N)
```

---

## ルール

1. **4 視点それぞれ最低 1 件は出す**: 該当なしは「軽微」レベルで埋める
2. **抽象的対策を出さない**: 「気をつける」「明示的に」「丁寧に」は禁止語彙
3. **transcript 引用を全 finding に**: 引用なしの finding は無効
4. **User 側の指摘を回避しない**: 遠慮で出力を歪めない
5. **過去 finding と重複したら「再発 N 回目」マーク**: 累積で重要度判定
6. **Skill Proposals の B（新規推奨）は具体的草案まで**: 抽象的アイデアで終わらない
7. **個人利用前提**: 免責文言・「投資助言ではない」式の保護文言は不要

## Red Flags - STOP and revise

以下が出力に含まれていたら kaizen 自体が失敗:
- 「全体的に良いセッションでした」
- 「特に問題なし」
- 「次回も気をつけて」
- 「丁寧に確認」「明示的に伝える」（抽象対策）
- transcript の直接引用が無い finding
- ユーザー側 0 件、Claude 側のみの findings
