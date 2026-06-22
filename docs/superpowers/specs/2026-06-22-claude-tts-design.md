---
title: Claude Code TTS 統合 — 直前応答をキーで読み上げ
date: 2026-06-22
status: design
---

# Claude Code TTS 統合 設計書

## 1. 概要

Claude Code の応答を macOS `say` で音声化する。発火はキー押下時のみ（自動発火なし）。Caps Lock + Z で「直前の応答を再生」、同じキーで「停止」。長文応答の途中で離席して戻ってきた時に、画面を見ずに耳で結論を拾える状態を作る。

## 2. 要件

| 項目 | 決定 |
|---|---|
| トリガー | Caps Lock + Z (Karabiner `simultaneous`) |
| 動作 | 同じキーで再生 ⇄ 停止のトグル |
| 自動発火 | しない (Stop hook は state file 更新のみ) |
| TTS エンジン | macOS 標準 `/usr/bin/say` |
| ボイス | Kyoko (日本語女性 Premium) |
| 話速 | 220 wpm (デフォルト 180 より速め) |
| 読み上げ範囲 | 直前の assistant ターン全文 |
| 前処理 | markdown 除去 + コード/表/URL を仕切り語に置換 |
| 競合回避 | Typeless / Handy 起動中は silent skip (feedback loop 防止) |
| 暴走上限 | 50,000 文字でカット |

## 3. アーキテクチャ

```
Claude Code session
        │
        │ assistant turn 完了
        ↓
┌───────────────────────────────────────────────────┐
│  Stop hook (stdin: JSON { transcript_path, ... }) │
│  $HOME/.claude/hooks/stop.sh                       │
│    ├─ 既存: collector.py (claude-stats)           │
│    └─ 追加: jq で transcript_path を取り出して     │
│       ~/.cache/claude-tts.last-transcript に保存  │
└───────────────────────────────────────────────────┘

                    (key down)
                         │
                         ↓
┌───────────────────────────────────────────────────┐
│  Karabiner: Caps Lock + Z (simultaneous)          │
│    shell_command: /Users/snakashima/dotfiles/bin/  │
│                   voice-out                        │
└───────────────────────┬───────────────────────────┘
                        ↓
┌───────────────────────────────────────────────────┐
│  bin/voice-out                                     │
│   1. トグル判定: pgrep -x say があれば pkill して  │
│      exit 0 (停止モード)                           │
│   2. 競合 check: Typeless/Handy 起動中なら exit 0  │
│   3. state file から transcript_path 読込         │
│   4. transcript JSONL の末尾 assistant ターン抽出 │
│   5. 前処理 (markdown → 仕切り語)                 │
│   6. /usr/bin/say -v Kyoko -r 220 &               │
└───────────────────────────────────────────────────┘
```

### 設計判断と理由

| 判断 | 理由 |
|---|---|
| 自動発火を採用しない | キー押下時のみ → ユーザーが聞きたい時だけ発火、サイレント作業との両立 |
| Stop hook を残す (path 記録のみ) | 自動発火なしでも「直前応答」を確実に特定するため、最新 transcript path を都度記録 |
| 状態はファイルで永続化 | shell またぎ・hook またぎで共有するには env var より file が確実 |
| トグルロジックを voice-out 内蔵 | 別 alias を増やすより、キー 1 つで再生/停止を完結させる方が UX 単純 |
| 競合 check (Typeless/Handy) | 録音中に TTS が出るとマイクがループ拾い、音声入力誤認識を招く |
| `-r 220` | macOS say デフォルト 180wpm は遅め、220wpm でテンポ良く |

## 4. コンポーネント

### 4.1 `bin/voice-out` (新規)

**責務**: トグル判定 → 競合 check → transcript 解決 → 末尾 assistant 抽出 → sanitize → say 起動。

**シグネチャ**:
```
voice-out                      # state file から transcript_path を解決 (キー押下経路の通常呼び出し)
voice-out --transcript PATH    # 手動テスト用、transcript path を直接指定
voice-out --text "..."         # 手動テスト用、テキストを直接渡す
```

**設定値**:
- `VOICE="${CLAUDE_TTS_VOICE:-Kyoko}"`
- `RATE="${CLAUDE_TTS_RATE:-220}"`
- `MAX_CHARS=50000`

**処理フロー**:
```
1. トグル判定
   pgrep -x say > /dev/null && { pkill -x say; exit 0; }

2. 競合 check
   pgrep -f /Applications/Typeless.app/Contents/MacOS/ && exit 0
   pgrep -x handy && exit 0

3. 入力解決 (どれか 1 つ)
   --text  → そのまま $TEXT
   --transcript → そのパスから末尾 assistant 抽出
   引数なし → ~/.cache/claude-tts.last-transcript を読み、その path から抽出

4. 末尾 assistant 抽出
   tail -n 200 "$transcript" | jq -rs '
     map(select(.type == "assistant"))
     | last
     | (.message.content // [])
     | map(select(.type == "text") | .text)
     | join("\n\n")'

5. 前処理 (sanitize)

6. 暴走上限
   text 長 > MAX_CHARS なら先頭 MAX_CHARS でカット + 「以下、省略します。」付加

7. 発話
   printf '%s' "$TEXT" | /usr/bin/say -v "$VOICE" -r "$RATE" &
```

### 4.2 `claude/hooks/stop.sh` (既存修正)

**変更**: 既存 collector.py 経路は不変。冒頭に 1 行追加して transcript_path を state file に記録する。

```bash
#!/bin/bash

CONFIG_DIR="$HOME/.config/claude-stats"

INPUT=$(cat)

# --- 追加: 最新 transcript_path を state file に記録 ---
mkdir -p "$HOME/.cache"
echo "$INPUT" | jq -r '.transcript_path // empty' \
  > "$HOME/.cache/claude-tts.last-transcript" 2>/dev/null
# ------------------------------------------------------

[ -f "$CONFIG_DIR/project-path" ] || exit 0
[ -f "$CONFIG_DIR/env" ] || exit 0

set -a; source "$CONFIG_DIR/env"; set +a

printf '%s' "$INPUT" | (cd "$(cat "$CONFIG_DIR/project-path")" && exec uv run python collector.py)
```

### 4.3 `karabiner/karabiner.json` (既存修正)

`complex_modifications.rules` に新ルールを追加:

```json
{
  "description": "Caps Lock + Z → voice-out (直前の Claude 応答を再生/停止トグル)",
  "manipulators": [
    {
      "type": "basic",
      "from": {
        "simultaneous": [
          { "key_code": "caps_lock" },
          { "key_code": "z" }
        ],
        "simultaneous_options": {
          "key_down_order": "strict",
          "to_after_key_up": []
        }
      },
      "to": [
        { "shell_command": "/Users/snakashima/dotfiles/bin/voice-out" }
      ]
    }
  ]
}
```

**単独 Caps Lock の挙動 (voice-toggle / F18 emit) は維持される**: Karabiner は `simultaneous` マッチを優先評価し、Z が押されない限り単独ルートに流れる。

### 4.4 ファイル所有関係

| ファイル | 種別 | git |
|---|---|---|
| `bin/voice-out` | 新規 | 管理 |
| `claude/hooks/stop.sh` | 修正 | 管理 |
| `karabiner/karabiner.json` | 修正 | 管理 |
| `test/voice-out.bats` | 新規 | 管理 |
| `~/.cache/claude-tts.last-transcript` | 状態 | 管理外 (揮発許容) |

## 5. データフロー

### 5.1 Stop hook の stdin JSON

```json
{
  "session_id": "3ce50f05-...",
  "transcript_path": "/Users/snakashima/.claude-work/projects/.../session.jsonl",
  "stop_hook_active": false,
  "cwd": "/Users/snakashima/dotfiles"
}
```

`stop.sh` は `transcript_path` のみ取り出して state file に書く。

### 5.2 transcript JSONL の構造

```jsonl
{"type":"user","message":{...},"uuid":"...","timestamp":"..."}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"..."},{"type":"tool_use","...":""}]},"uuid":"...","timestamp":"..."}
{"type":"tool_result","message":{...}}
```

読み上げ対象は **末尾 `type=="assistant"` 行の `message.content[]` のうち `type=="text"`** のみ。

### 5.3 前処理 (sanitize) の段階

```
入力 (markdown 含む raw text)
 ↓ [1] code block 置換: ``` ... ``` → "コードブロック省略。"
 ↓ [2] table 置換: `| ... | ... |` 連続行 → "表省略。"
 ↓ [3] long URL 置換: https?://\S{30,} → "リンク。"
 ↓ [4] markdown 記号除去: # / - / ** / ` / >
 ↓ [5] 空行圧縮: \n{3,} → \n\n
出力 (say に渡す text)
```

### 5.4 end-to-end フロー

```
[キー押下] Caps Lock + Z
    │
    ↓ Karabiner simultaneous match
    │
[起動] /Users/snakashima/dotfiles/bin/voice-out
    │
    ├ pgrep say あり → pkill → exit 0 (停止)
    │
    └ pgrep say なし → 続行
        │
        ↓ ~/.cache/claude-tts.last-transcript 読込
        │
        ↓ tail | jq で末尾 assistant text 抽出
        │
        ↓ sanitize (5 段階)
        │
        ↓ printf | say -v Kyoko -r 220 &
        │
       🔊 Kyoko の声で読み上げ
```

## 6. エラーハンドリング

voice-out は **best-effort で silent fail** を基本方針とする。Stop hook 経由 / キー経由いずれも、失敗してもユーザー体験を阻害しない。

| # | ケース | 挙動 |
|---|---|---|
| 1 | Typeless / Handy 起動中 | `exit 0`、feedback loop 回避 |
| 2 | state file 不在 (Stop hook が一度も走っていない) | `exit 0` |
| 3 | transcript ファイル不在 | `exit 0` |
| 4 | transcript JSONL が壊れている | `exit 0` (jq の `-e` は使わない) |
| 5 | 末尾 assistant ターンに text ブロックなし | `exit 0` |
| 6 | sanitize 後のテキストが空 | `exit 0` |
| 7 | テキストが 50,000 文字超 | 先頭 50,000 でカット + 「以下省略」 |
| 8 | 前 say プロセスが残存 (連打誤発火) | トグル判定で `pkill -x say` して終了 |
| 9 | `/usr/bin/say` 不在 | `exit 0` (macOS 限定機能、silent fail) |
| 10 | shell 特殊文字 (`` ` `` `$` `!`) を含むテキスト | 引数渡しではなく stdin パイプで say に渡し、injection を回避 |

### デバッグ補助

`CLAUDE_TTS_DEBUG=1` 環境変数が立っている時のみ `/tmp/voice-out.log` に詳細を吐く。

```bash
log() {
  [ -n "$CLAUDE_TTS_DEBUG" ] && \
    printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >> /tmp/voice-out.log
}
```

## 7. テスト戦略

| 領域 | テスト方式 | 理由 |
|---|---|---|
| sanitize ロジック | bats 自動 | 純粋関数、回帰しやすい |
| transcript 抽出 (jq) | 手動 | Claude Code が JSON 構造変更したら壊れる前提 |
| say 起動 / kill | 手動 | macOS 固有 |
| Karabiner 統合 | 手動 | キー入力は CI 不可 |

### 7.1 単体テスト (`test/voice-out.bats`)

```bash
@test "code block を仕切り語に置換" {
  result=$(sanitize "$'```sh\necho hi\n```'")
  [ "$result" = "コードブロック省略。" ]
}

@test "table を仕切り語に置換" {
  result=$(sanitize $'| a | b |\n|---|---|\n| 1 | 2 |')
  [ "$result" = "表省略。" ]
}

@test "長 URL を リンク に置換" {
  result=$(sanitize "see https://github.com/example/repo/pull/12345 ok")
  [[ "$result" == *"リンク。"* ]]
}

@test "markdown 見出し記号を除去" {
  result=$(sanitize $'# Title\n## Subtitle')
  [[ "$result" != *"#"* ]]
}

@test "bold 記号を除去し中身は残す" {
  result=$(sanitize "**重要**な点")
  [ "$result" = "重要な点" ]
}

@test "空入力で空出力" {
  result=$(sanitize "")
  [ -z "$result" ]
}

@test "改行 3 連続を 2 連続に圧縮" {
  result=$(sanitize $'a\n\n\n\nb')
  [ "$result" = $'a\n\nb' ]
}
```

ローカル実行: `bats test/voice-out.bats`。CI は使わない。

### 7.2 統合 sanity test (手動)

```bash
# A. 直接テキスト渡し
voice-out --text "こんにちは、テストです"

# B. transcript 引数指定
voice-out --transcript /tmp/sample.jsonl

# C. トグル動作
voice-out --text "$(printf '%.0s長い文章' {1..50})"
voice-out   # 2 回目で停止

# D. 競合 check
open -a Typeless
voice-out --text "テスト"   # silent skip

# E. キー押下経路 (Caps Lock + Z)
# → Karabiner 経由で voice-out が起動し、直前応答が読まれる
```

### 7.3 hook 経路の sanity test

```bash
echo '{"transcript_path":"/tmp/dummy.jsonl"}' | $HOME/.claude/hooks/stop.sh
cat ~/.cache/claude-tts.last-transcript
# Expected: /tmp/dummy.jsonl
```

## 8. 未確定リスクと対応

| リスク | 影響 | 対応 |
|---|---|---|
| Stop hook の stdin JSON 構造が想定と違う | state file が空になり voice-out が exit 0 | 実装初手で `echo "$INPUT" > /tmp/last_stop_input.json` の debug 行を入れて実機確認、確認後削除 |
| Karabiner `simultaneous` の押下タイムアウトが厳しい | Caps Lock + Z が反応しない | `simultaneous_options.detect_key_down_uninterruptedly` や timeout 調整、または順次押下式の `mandatory` modifier 案へ切替 |
| Handy 起動中=mic 専有とは限らない | Handy 起動でも読み上げ可能なのに skip される | 将来 `~/.cache/claude-tts.force-on` フラグで override 余地を残す |
| Kyoko が日英混在テキストを読みづらい | 英語部分が日本語訛りで聞きづらい | 初期は許容、必要なら「言語判定で Kyoko/Alex 切替」を後付け |
| transcript JSONL のスキーマ変更 (Claude Code 側) | jq 抽出が壊れる | スキーマが変わったら error log を見て jq 式を更新 |
| 連打誤発火 | 押すたびに say が起動/停止のループ | トグル設計が吸収、追加対応不要 |

## 9. 既存システムへの影響

| 既存 | 影響 |
|---|---|
| `voice-switch` / `voice-toggle` / `voice-glossary-list` | 影響なし。命名 (`voice-out`) で同シリーズに連なる |
| Karabiner 既存ルール (単独 Caps Lock, Fn+ 系) | 影響なし。Z との同時押しのみ新ルートで分岐 |
| `claude-stats` collector.py | 影響なし。stop.sh の追加処理は collector 起動前 |
| Handy / Typeless 音声入力 | 影響なし。voice-out は競合検出で silent skip |

## 10. 実装の段階分け（writing-plans への引き継ぎ）

writing-plans が以下の順序で実装計画を作成することを想定:

1. `bin/voice-out` 骨子 (toggle + 競合 check + --text 経路) — `voice-out --text "hi"` で Kyoko が喋る最小動作確認
2. sanitize 関数 + bats テスト — 自動テスト緑化
3. transcript 抽出 (`--transcript` 経路) — sample JSONL で動作確認
4. state file 読込 (引数なし経路) + Stop hook 修正 — Claude Code 1 ターン回して state file が更新されるか確認
5. Karabiner 統合 — Caps Lock + Z で発火確認、単独 Caps Lock の voice-toggle が壊れないことを確認
6. 暴走上限 + デバッグログ + ドキュメント整備

各ステップで verification 可能な単位に分割されている。
