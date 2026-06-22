# Claude Code TTS 統合 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Caps Lock + Z で直前の Claude Code 応答を macOS `say` (Kyoko) で読み上げる。同じキーで再生 ⇄ 停止トグル、自動発火なし。

**Architecture:** Karabiner `simultaneous` でキー押下を捕捉し `bin/voice-out` を起動する。voice-out はトグル判定 → 競合 check → state file から transcript_path 解決 → 末尾 assistant 抽出 → sanitize → say の単線パイプライン。Stop hook は最新 transcript_path を `~/.cache/claude-tts.last-transcript` に書くだけの最小役割。

**Tech Stack:** bash 3.2 (macOS 標準), jq, /usr/bin/say (Kyoko Premium), Karabiner-Elements, bats-core (test only).

## Global Constraints

- 対象 OS: macOS のみ (Linux では silent fail)
- bash 3.2 互換 (`declare -A` / `${var,,}` 等の 4+ 機能は禁止)
- 失敗は silent (best-effort)、stderr/stdout に常用ログを出さない (`CLAUDE_TTS_DEBUG=1` 時のみ `/tmp/voice-out.log`)
- ボイス: `Kyoko`、話速: `180 wpm` (macOS say デフォルト、聴き取り重視) を初期値とし、`CLAUDE_TTS_VOICE` / `CLAUDE_TTS_RATE` 環境変数で上書き可能
- 暴走上限: 50,000 文字でカット
- state file: `~/.cache/claude-tts.last-transcript` (存在 = 直前 transcript path、不在 = 何もしない)
- 競合: Typeless プロセス起動中 (`pgrep -f /Applications/Typeless.app/Contents/MacOS/`) または Handy プロセス起動中 (`pgrep -x handy`) なら silent skip
- shell injection 対策: say への入力は引数渡しではなく stdin pipe (`printf '%s' "$text" | say ...`)
- 既存 `voice-switch` / `voice-toggle` / `voice-glossary-list` の挙動を壊さないこと
- 単独 Caps Lock の挙動 (Karabiner で voice-toggle 起動 or F18 emit) を壊さないこと
- 既存 `claude/hooks/stop.sh` の collector.py 経路を壊さないこと
- spec: `docs/superpowers/specs/2026-06-22-claude-tts-design.md`

---

## File Structure

| ファイル | 種別 | 責務 |
|---|---|---|
| `bin/voice-out` | 新規 | トグル判定 → 競合 check → transcript 解決 → sanitize → say 起動の単線パイプライン |
| `claude/hooks/stop.sh` | 修正 | 既存 collector.py 経路は不変、冒頭に「stdin JSON から transcript_path を取り出して state file に書く」処理を追加 |
| `karabiner/karabiner.json` | 修正 | `complex_modifications.rules` に Caps Lock + Z → voice-out のルール追加 |
| `test/voice-out.bats` | 新規 | sanitize 関数の 7 ケース自動テスト |

---

## Task 0: 依存導入とテストディレクトリ準備

**Files:**
- Modify (実行): Homebrew で bats-core を導入
- Create: `test/` ディレクトリ

**Interfaces:**
- Produces: `bats` コマンドが PATH 上で利用可能、`test/` ディレクトリが存在

- [ ] **Step 1: bats-core を Homebrew で導入**

```bash
brew install bats-core
```

Expected: 既存 install または "Pouring bats-core-... " の出力。

- [ ] **Step 2: バージョン確認**

```bash
bats --version
```

Expected: `Bats X.Y.Z` 形式の出力 (どのバージョンでも可)。

- [ ] **Step 3: Brewfile に追記**

`/Users/snakashima/dotfiles/Brewfile` を Read で読み、`brew` エントリの並びに合わせて以下を追加 (Edit で挿入):

```
brew "bats-core"
```

挿入位置: 既存 `brew "..."` 行の末尾（アルファベット順を維持できる位置があればそこ）。

- [ ] **Step 4: test/ ディレクトリ作成**

```bash
mkdir -p /Users/snakashima/dotfiles/test
```

Expected: エラーなし。

- [ ] **Step 5: Commit**

```bash
cd /Users/snakashima/dotfiles
git add Brewfile
git commit -m "chore(deps): bats-core を追加 (voice-out の sanitize 関数テスト用)"
```

---

## Task 1: bin/voice-out 骨子 — `--text` で Kyoko が喋るところまで

**Files:**
- Create: `/Users/snakashima/dotfiles/bin/voice-out`

**Interfaces:**
- Consumes: なし
- Produces: `voice-out --text "..."` を叩くと Kyoko の声で読み上げる。終了コード 0。`/usr/bin/say` を background (`&`) で起動するため、シェルに即制御が戻る。

- [ ] **Step 1: 失敗確認 (file 不在)**

```bash
test -f /Users/snakashima/dotfiles/bin/voice-out
echo "exit=$?"
```

Expected: `exit=1` (まだ無いので)。

- [ ] **Step 2: bin/voice-out を新規作成**

`/Users/snakashima/dotfiles/bin/voice-out` を以下の内容で Write:

```bash
#!/bin/bash
# Speak the most recent Claude Code assistant turn via macOS say.
#
# Modes:
#   voice-out                     stdin: hook JSON (Stop hook 経由)
#                                 引数なし: state file から transcript path を読む
#   voice-out --text "..."        渡された text をそのまま say (sanitize はかける)
#   voice-out --transcript PATH   指定 transcript JSONL の末尾 assistant ターンを抽出
#
# 失敗は silent (best-effort)。CLAUDE_TTS_DEBUG=1 で /tmp/voice-out.log に詳細を吐く。

VOICE="${CLAUDE_TTS_VOICE:-Kyoko}"
RATE="${CLAUDE_TTS_RATE:-180}"
MAX_CHARS=50000

log() {
  [ -n "$CLAUDE_TTS_DEBUG" ] && \
    printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >> /tmp/voice-out.log
}

# --- 引数解析 (Task 1 では --text のみ対応) ---
TEXT=""
case "${1:-}" in
  --text)
    TEXT="${2:-}"
    ;;
  "")
    log "no args (state file path not yet implemented)"
    exit 0
    ;;
  *)
    log "unknown arg: $1"
    exit 0
    ;;
esac

[ -z "$TEXT" ] && { log "empty text"; exit 0; }

log "speaking: ${TEXT:0:80}..."
printf '%s' "$TEXT" | /usr/bin/say -v "$VOICE" -r "$RATE" &
```

- [ ] **Step 3: 実行権を付与**

```bash
chmod +x /Users/snakashima/dotfiles/bin/voice-out
```

Expected: エラーなし。

- [ ] **Step 4: 動作確認 (Kyoko の声が出るか)**

```bash
/Users/snakashima/dotfiles/bin/voice-out --text "こんにちは、テストです"
```

Expected: 数秒以内に Kyoko の声で「こんにちは、テストです」と聞こえる。シェルは即プロンプトに戻る。

- [ ] **Step 5: 失敗ケースの動作確認 (空テキスト)**

```bash
/Users/snakashima/dotfiles/bin/voice-out --text ""
echo "exit=$?"
```

Expected: 無音、`exit=0`。

- [ ] **Step 6: デバッグログ確認**

```bash
CLAUDE_TTS_DEBUG=1 /Users/snakashima/dotfiles/bin/voice-out --text "debug test"
sleep 1
tail -3 /tmp/voice-out.log
```

Expected: `speaking: debug test...` のような行が `/tmp/voice-out.log` に追記されている。

- [ ] **Step 7: Commit**

```bash
cd /Users/snakashima/dotfiles
git add bin/voice-out
git commit -m "feat(voice-out): --text 経路の最小実装 (Kyoko で読み上げ)"
```

---

## Task 2: トグル動作 (再生 ⇄ 停止)

**Files:**
- Modify: `/Users/snakashima/dotfiles/bin/voice-out`

**Interfaces:**
- Consumes: Task 1 で作った `voice-out --text`
- Produces: voice-out を 2 度叩くと、2 度目は走行中の say を pkill して exit 0。3 度目で再度再生。

- [ ] **Step 1: 失敗確認 (今は 2 度目も読む)**

長文を再生し、すぐに 2 度目を実行して挙動を確認:

```bash
/Users/snakashima/dotfiles/bin/voice-out --text "これはとても長いテキストです。$(printf '%.0s長い文章。' {1..30})"
sleep 1
/Users/snakashima/dotfiles/bin/voice-out --text "二回目のテキスト"
```

Expected (現状): **両方が同時に読まれて重なる** = NG 動作を観察。

- [ ] **Step 2: トグル判定をスクリプト冒頭に追加**

`bin/voice-out` の引数解析より前 (`VOICE=...` の定義の後、`log()` 関数の後) にトグル判定を追加。Edit ツールで `case "${1:-}" in` の直前に以下を挿入:

```bash
# --- トグル判定: 既に say が走っていれば kill して終了 ---
if /usr/bin/pgrep -x say >/dev/null 2>&1; then
  log "say already running, killing (toggle off)"
  /usr/bin/pkill -x say 2>/dev/null
  exit 0
fi

```

- [ ] **Step 3: 動作確認 (停止モード)**

長文を再生開始 → 1 秒後に 2 度目を叩いて停止することを確認:

```bash
/Users/snakashima/dotfiles/bin/voice-out --text "これはとても長いテキストです。$(printf '%.0s長い文章。' {1..30})"
sleep 1
/Users/snakashima/dotfiles/bin/voice-out --text "停止するはず"
```

Expected: 1 度目の読み上げが 2 度目の実行と同時に停止し、2 度目のテキストは読まれない。

- [ ] **Step 4: 動作確認 (再生モード復帰)**

```bash
sleep 2
/Users/snakashima/dotfiles/bin/voice-out --text "再生再開のテスト"
```

Expected: 「再生再開のテスト」が読まれる。

- [ ] **Step 5: Commit**

```bash
cd /Users/snakashima/dotfiles
git add bin/voice-out
git commit -m "feat(voice-out): pgrep/pkill で再生 ⇄ 停止のトグルを追加"
```

---

## Task 3: 競合 check (Typeless/Handy 起動中は silent skip)

**Files:**
- Modify: `/Users/snakashima/dotfiles/bin/voice-out`

**Interfaces:**
- Consumes: Task 2 のトグル判定
- Produces: Typeless または Handy が起動中なら voice-out が exit 0 して say を起動しない (feedback loop 防止)

- [ ] **Step 1: 失敗確認 (今は Typeless 起動中でも読まれる)**

```bash
open -a Typeless
sleep 3
/Users/snakashima/dotfiles/bin/voice-out --text "Typeless 起動中だけど読まれる"
```

Expected (現状): Kyoko の声が聞こえてしまう = NG 動作。

(確認後) Typeless を quit:

```bash
osascript -e 'quit app "Typeless"'
```

- [ ] **Step 2: 競合 check をスクリプトに追加**

トグル判定の直後 (引数解析より前) に追加。Edit で挿入:

```bash
# --- 競合 check: Typeless / Handy が握っている時は silent skip ---
if /usr/bin/pgrep -f "/Applications/Typeless.app/Contents/MacOS/" >/dev/null 2>&1; then
  log "Typeless running, skipping to avoid feedback loop"
  exit 0
fi
if /usr/bin/pgrep -x handy >/dev/null 2>&1; then
  log "Handy running, skipping to avoid feedback loop"
  exit 0
fi

```

- [ ] **Step 3: 動作確認 (Typeless 起動中)**

```bash
open -a Typeless
sleep 3
/Users/snakashima/dotfiles/bin/voice-out --text "Typeless 起動中なら聞こえないはず"
sleep 2
echo "no sound should have played"
```

Expected: 無音、メッセージのみ表示。

- [ ] **Step 4: 動作確認 (Handy 起動中) ※ Handy 未起動なら skip 可**

```bash
# Handy が動いている場合のみ
/usr/bin/pgrep -x handy >/dev/null && {
  /Users/snakashima/dotfiles/bin/voice-out --text "Handy 起動中なら聞こえないはず"
  echo "no sound should have played"
}
```

Expected: Handy 起動中なら無音、起動していなければスキップ。

- [ ] **Step 5: 動作確認 (両方停止状態で再生復帰)**

```bash
osascript -e 'quit app "Typeless"' 2>/dev/null
osascript -e 'quit app "Handy"' 2>/dev/null
sleep 3
/Users/snakashima/dotfiles/bin/voice-out --text "両方停止なら聞こえる"
```

Expected: Kyoko の声で読まれる。

- [ ] **Step 6: Commit**

```bash
cd /Users/snakashima/dotfiles
git add bin/voice-out
git commit -m "feat(voice-out): Typeless/Handy 起動中は silent skip (feedback loop 回避)"
```

---

## Task 4: sanitize 関数 + bats テスト

**Files:**
- Modify: `/Users/snakashima/dotfiles/bin/voice-out` (sanitize 関数を追加し、--text 経路で適用)
- Create: `/Users/snakashima/dotfiles/test/voice-out.bats`

**Interfaces:**
- Consumes: Task 3 までの voice-out
- Produces: sanitize 関数 (`sanitize "$raw"` → markdown 除去 + 仕切り語置換後の text を stdout に出す)。`test/voice-out.bats` で 7 ケース緑化。

- [ ] **Step 1: 失敗テストファイルを作成**

`/Users/snakashima/dotfiles/test/voice-out.bats` を以下の内容で Write:

```bash
#!/usr/bin/env bats

# voice-out スクリプトを source して sanitize 関数を呼ぶ
load_voice_out() {
  # voice-out 自体は実行されると say を呼んでしまうので、
  # sanitize 関数だけ抽出して評価する
  eval "$(sed -n '/^sanitize()/,/^}/p' "${BATS_TEST_DIRNAME}/../bin/voice-out")"
}

setup() {
  load_voice_out
}

@test "code block を仕切り語に置換" {
  result=$(sanitize $'```sh\necho hi\n```')
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

@test "改行 3 連続以上を 2 連続に圧縮" {
  result=$(sanitize $'a\n\n\n\nb')
  [ "$result" = $'a\n\nb' ]
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

```bash
cd /Users/snakashima/dotfiles
bats test/voice-out.bats
```

Expected: 全 7 ケース FAIL (sanitize 関数がまだ無いため)。

- [ ] **Step 3: sanitize 関数を voice-out に追加**

`bin/voice-out` の `log()` 関数の直後に以下を挿入 (Edit で `log()` ブロックの直後 + 空行を挟む):

```bash
# --- sanitize: markdown を素読みできる平文へ変換 ---
sanitize() {
  printf '%s' "$1" \
    | /usr/bin/awk '
        BEGIN { inc = 0 }
        /^```/ {
          if (inc == 0) { inc = 1 }
          else          { inc = 0; print "コードブロック省略。" }
          next
        }
        inc == 0 { print }
      ' \
    | /usr/bin/awk '
        BEGIN { in_tbl = 0 }
        /^\|.*\|$/ {
          if (in_tbl == 0) { print "表省略。"; in_tbl = 1 }
          next
        }
        { in_tbl = 0; print }
      ' \
    | /usr/bin/sed -E 's|https?://[^[:space:]]+|リンク。|g' \
    | /usr/bin/sed -E 's/^#+[[:space:]]*//' \
    | /usr/bin/sed -E 's/^[[:space:]]*[-*][[:space:]]+//' \
    | /usr/bin/sed -E 's/\*\*([^*]+)\*\*/\1/g' \
    | /usr/bin/sed -E 's/`([^`]+)`/\1/g' \
    | /usr/bin/sed -E 's/^>[[:space:]]*//' \
    | /usr/bin/awk '
        BEGIN { blank = 0 }
        /^$/ { blank++; if (blank <= 1) print; next }
        { blank = 0; print }
      '
}

```

- [ ] **Step 4: --text 経路で sanitize を通すよう修正**

`bin/voice-out` の `printf '%s' "$TEXT" | /usr/bin/say ...` の直前で TEXT を sanitize する。Edit で以下に置換:

旧:
```bash
[ -z "$TEXT" ] && { log "empty text"; exit 0; }

log "speaking: ${TEXT:0:80}..."
printf '%s' "$TEXT" | /usr/bin/say -v "$VOICE" -r "$RATE" &
```

新:
```bash
[ -z "$TEXT" ] && { log "empty text"; exit 0; }

TEXT="$(sanitize "$TEXT")"
[ -z "$TEXT" ] && { log "sanitized to empty"; exit 0; }

log "speaking: ${TEXT:0:80}..."
printf '%s' "$TEXT" | /usr/bin/say -v "$VOICE" -r "$RATE" &
```

- [ ] **Step 5: テストを走らせて緑化を確認**

```bash
cd /Users/snakashima/dotfiles
bats test/voice-out.bats
```

Expected: 7 / 7 ok。

```
voice-out.bats
 ✓ code block を仕切り語に置換
 ✓ table を仕切り語に置換
 ✓ 長 URL を リンク に置換
 ✓ markdown 見出し記号を除去
 ✓ bold 記号を除去し中身は残す
 ✓ 空入力で空出力
 ✓ 改行 3 連続以上を 2 連続に圧縮

7 tests, 0 failures
```

- [ ] **Step 6: 動作確認 (markdown を含む text を読ませる)**

```bash
/Users/snakashima/dotfiles/bin/voice-out --text $'# 見出し\n**重要**な点。コードは ```bash\necho hi\n``` 省略。'
```

Expected: Kyoko が「見出し。重要な点。コードはコードブロック省略。省略。」のように読む (記号を読まない)。

- [ ] **Step 7: Commit**

```bash
cd /Users/snakashima/dotfiles
git add bin/voice-out test/voice-out.bats
git commit -m "feat(voice-out): sanitize 関数 (markdown→仕切り語) + bats テスト 7 ケース"
```

---

## Task 5: transcript 抽出 (`--transcript` 経路)

**Files:**
- Modify: `/Users/snakashima/dotfiles/bin/voice-out` (引数解析に `--transcript` を追加 + 末尾 assistant 抽出関数)

**Interfaces:**
- Consumes: Task 4 までの voice-out
- Produces: `voice-out --transcript /path/to/session.jsonl` が末尾 assistant ターンを抽出して読む

- [ ] **Step 1: サンプル transcript を用意**

`/tmp/sample-transcript.jsonl` を以下の内容で Write:

```jsonl
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Hello"}]},"uuid":"u1","timestamp":"2026-06-22T10:00:00Z"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"これは古い応答です。"}]},"uuid":"a1","timestamp":"2026-06-22T10:00:01Z"}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"何時ですか"}]},"uuid":"u2","timestamp":"2026-06-22T10:01:00Z"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{}},{"type":"text","text":"現在は午前 10 時 1 分です。"}]},"uuid":"a2","timestamp":"2026-06-22T10:01:01Z"}
```

- [ ] **Step 2: 抽出関数の単体動作確認 (jq の挙動を先に検証)**

```bash
/usr/bin/tail -n 200 /tmp/sample-transcript.jsonl \
  | jq -rs 'map(select(.type == "assistant")) | last | (.message.content // []) | map(select(.type == "text") | .text) | join("\n\n")'
```

Expected: `現在は午前 10 時 1 分です。` (古い応答ではなく最新の assistant の text のみ、tool_use は除外)。

- [ ] **Step 3: extract_latest_assistant 関数を voice-out に追加**

`bin/voice-out` の `sanitize()` 関数の直後に以下を挿入:

```bash
# --- 末尾 assistant ターンの text ブロックを抽出 ---
extract_latest_assistant() {
  local transcript="$1"
  [ -f "$transcript" ] || { log "transcript not found: $transcript"; return 1; }
  /usr/bin/tail -n 200 "$transcript" 2>/dev/null \
    | /opt/homebrew/bin/jq -rs '
        map(select(.type == "assistant"))
        | last
        | (.message.content // [])
        | map(select(.type == "text") | .text)
        | join("\n\n")
      ' 2>/dev/null
}

```

- [ ] **Step 4: 引数解析に `--transcript` を追加**

`bin/voice-out` の `case "${1:-}" in` ブロックを以下に置換:

旧:
```bash
case "${1:-}" in
  --text)
    TEXT="${2:-}"
    ;;
  "")
    log "no args (state file path not yet implemented)"
    exit 0
    ;;
  *)
    log "unknown arg: $1"
    exit 0
    ;;
esac
```

新:
```bash
case "${1:-}" in
  --text)
    TEXT="${2:-}"
    ;;
  --transcript)
    TRANSCRIPT="${2:-}"
    [ -z "$TRANSCRIPT" ] && { log "--transcript needs path"; exit 0; }
    TEXT="$(extract_latest_assistant "$TRANSCRIPT")"
    ;;
  "")
    log "no args (state file path not yet implemented)"
    exit 0
    ;;
  *)
    log "unknown arg: $1"
    exit 0
    ;;
esac
```

- [ ] **Step 5: 動作確認**

```bash
/Users/snakashima/dotfiles/bin/voice-out --transcript /tmp/sample-transcript.jsonl
```

Expected: Kyoko が「現在は午前 10 時 1 分です。」と読む。

- [ ] **Step 6: 失敗ケース確認 (存在しない path)**

```bash
/Users/snakashima/dotfiles/bin/voice-out --transcript /tmp/does-not-exist.jsonl
echo "exit=$?"
```

Expected: 無音、`exit=0`。

- [ ] **Step 7: Commit**

```bash
cd /Users/snakashima/dotfiles
rm /tmp/sample-transcript.jsonl
git add bin/voice-out
git commit -m "feat(voice-out): --transcript で JSONL 末尾 assistant 抽出 (tool_use 除外)"
```

---

## Task 6: state file 読込 (引数なし経路) + Stop hook 修正

**Files:**
- Modify: `/Users/snakashima/dotfiles/bin/voice-out` (引数なし時に state file を読む)
- Modify: `/Users/snakashima/dotfiles/claude/hooks/stop.sh` (state file 書き込み 1 行追加)

**Interfaces:**
- Consumes: Task 5 までの voice-out (`--transcript` 経路)
- Produces: 引数なし `voice-out` が `~/.cache/claude-tts.last-transcript` を読んで `--transcript` と同じ動作。Stop hook が走るたびに state file が最新化される。

- [ ] **Step 1: stop.sh の現状を確認 (壊さないため)**

```bash
cat /Users/snakashima/dotfiles/claude/hooks/stop.sh
```

Expected: collector.py を起動するロジックがある。

- [ ] **Step 2: 引数なし経路を voice-out に実装**

`bin/voice-out` の `case "${1:-}" in` の `""` 分岐を以下に書き換える:

旧:
```bash
  "")
    log "no args (state file path not yet implemented)"
    exit 0
    ;;
```

新:
```bash
  "")
    STATE_FILE="$HOME/.cache/claude-tts.last-transcript"
    [ -f "$STATE_FILE" ] || { log "state file not found"; exit 0; }
    TRANSCRIPT="$(cat "$STATE_FILE" 2>/dev/null)"
    [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ] && { log "transcript invalid: $TRANSCRIPT"; exit 0; }
    TEXT="$(extract_latest_assistant "$TRANSCRIPT")"
    ;;
```

- [ ] **Step 3: state file がない状態で引数なし voice-out を試す**

```bash
rm -f ~/.cache/claude-tts.last-transcript
/Users/snakashima/dotfiles/bin/voice-out
echo "exit=$?"
```

Expected: 無音、`exit=0`。

- [ ] **Step 4: state file を手動で書いて引数なし voice-out を試す**

```bash
# Task 5 でテストした sample を再生成
cat > /tmp/sample-transcript.jsonl <<'EOF'
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Hello"}]},"uuid":"u1","timestamp":"2026-06-22T10:00:00Z"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"テスト応答です。"}]},"uuid":"a1","timestamp":"2026-06-22T10:00:01Z"}
EOF
mkdir -p ~/.cache
echo "/tmp/sample-transcript.jsonl" > ~/.cache/claude-tts.last-transcript

/Users/snakashima/dotfiles/bin/voice-out
```

Expected: Kyoko が「テスト応答です。」と読む。

- [ ] **Step 5: stop.sh に state file 書き込みを追加**

`claude/hooks/stop.sh` を以下に書き換え (現在の内容を保持しつつ追加):

```bash
#!/bin/bash

CONFIG_DIR="$HOME/.config/claude-stats"

INPUT=$(cat)

# --- 追加: 最新 transcript_path を voice-out 用 state file に記録 ---
mkdir -p "$HOME/.cache" 2>/dev/null
printf '%s' "$INPUT" | /opt/homebrew/bin/jq -r '.transcript_path // empty' \
  > "$HOME/.cache/claude-tts.last-transcript" 2>/dev/null

# --- 既存: claude-stats collector ---
[ -f "$CONFIG_DIR/project-path" ] || exit 0
[ -f "$CONFIG_DIR/env" ] || exit 0

set -a
source "$CONFIG_DIR/env"
set +a

printf '%s' "$INPUT" | (cd "$(cat "$CONFIG_DIR/project-path")" && exec uv run python collector.py)
```

- [ ] **Step 6: stop.sh の hook stdin シミュレートで動作確認**

```bash
# state file をクリアして hook を fake 入力で叩く
rm -f ~/.cache/claude-tts.last-transcript
echo '{"transcript_path":"/tmp/fake-session.jsonl","session_id":"xxx","stop_hook_active":false,"cwd":"/tmp"}' \
  | bash /Users/snakashima/dotfiles/claude/hooks/stop.sh
cat ~/.cache/claude-tts.last-transcript
```

Expected: `/tmp/fake-session.jsonl` が出力される。collector.py 経路は config が無いので silent exit のはず。

- [ ] **Step 7: 実 Claude Code セッション 1 ターン経由で動作確認**

Claude Code でこのセッションに「test ping」とでも送信し、応答が返るのを待ってから:

```bash
cat ~/.cache/claude-tts.last-transcript
ls -la "$(cat ~/.cache/claude-tts.last-transcript)" 2>&1 | head -1
```

Expected: 実セッションの transcript path (`.claude-work/projects/.../session.jsonl`) が記載されている。ファイルが存在する。

その上で:

```bash
/Users/snakashima/dotfiles/bin/voice-out
```

Expected: 直前 (この test ping への応答) を Kyoko が読み上げる。

- [ ] **Step 8: クリーンアップ + Commit**

```bash
cd /Users/snakashima/dotfiles
rm -f /tmp/sample-transcript.jsonl
git add bin/voice-out claude/hooks/stop.sh
git commit -m "feat(voice-out,stop-hook): state file 経由で引数なし voice-out が直前応答を読む"
```

---

## Task 7: 暴走上限 + デバッグログ強化

**Files:**
- Modify: `/Users/snakashima/dotfiles/bin/voice-out`

**Interfaces:**
- Consumes: Task 6 までの voice-out
- Produces: 50,000 文字を超える応答が来た時、先頭 50,000 でカットして「以下、省略します。」を付加。`CLAUDE_TTS_DEBUG=1` の時に十分なログが出る。

- [ ] **Step 1: 上限カットを実装**

`bin/voice-out` の `TEXT="$(sanitize "$TEXT")"` の直後に以下を挿入:

```bash
if [ ${#TEXT} -gt $MAX_CHARS ]; then
  log "text too long (${#TEXT} chars), truncating to $MAX_CHARS"
  TEXT="${TEXT:0:$MAX_CHARS}。以下、省略します。"
fi

```

- [ ] **Step 2: 動作確認 (50,000 文字を超える text)**

```bash
LONG=$(/usr/bin/python3 -c "print('長い文章。' * 12000)")
echo "len = ${#LONG}"
CLAUDE_TTS_DEBUG=1 /Users/snakashima/dotfiles/bin/voice-out --text "$LONG"
sleep 1
tail -5 /tmp/voice-out.log
```

Expected: ログに `text too long (XXXXXX chars), truncating to 50000` が出る。Kyoko が長文を読み始め、最後に「以下、省略します。」と言う。

- [ ] **Step 3: 確認後、走行中の say を止める**

```bash
/Users/snakashima/dotfiles/bin/voice-out --text "stop"
```

Expected: トグル判定で前の say を止めて exit 0 (2 度目のテキストは読まれない)。

- [ ] **Step 4: Commit**

```bash
cd /Users/snakashima/dotfiles
git add bin/voice-out
git commit -m "feat(voice-out): 50,000 文字超で打ち切り + デバッグログ拡充"
```

---

## Task 8: Karabiner 統合 (Caps Lock + Z)

**Files:**
- Modify: `/Users/snakashima/dotfiles/karabiner/karabiner.json`

**Interfaces:**
- Consumes: Task 7 までの voice-out
- Produces: Caps Lock を押しながら Z で `bin/voice-out` が起動する。単独 Caps Lock の挙動 (voice-toggle 起動 / F18 emit) は不変。

- [ ] **Step 1: karabiner.json の現状を確認 (破壊回避)**

```bash
/opt/homebrew/bin/jq '.profiles[0].complex_modifications.rules | map(.description)' /Users/snakashima/dotfiles/karabiner/karabiner.json
```

Expected: 既存ルールの description リスト。新ルール追加前のスナップショット。

- [ ] **Step 2: 新ルールを追加**

`karabiner/karabiner.json` の `complex_modifications.rules` 配列に以下を追加 (Edit で配列の末尾、`]` の直前に既存ルールとの間に `,` を入れて挿入):

```json
,
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

- [ ] **Step 3: JSON valid 性を確認**

```bash
/opt/homebrew/bin/jq '.' /Users/snakashima/dotfiles/karabiner/karabiner.json > /dev/null && echo "JSON OK"
```

Expected: `JSON OK`。

- [ ] **Step 4: Karabiner に反映 (~/.config/karabiner に symlink されているはず)**

```bash
ls -la ~/.config/karabiner/karabiner.json
diff /Users/snakashima/dotfiles/karabiner/karabiner.json ~/.config/karabiner/karabiner.json
```

Expected: 同一 inode の symlink、または diff なし。差分がある場合は dotfiles 側の setup を再確認。

(必要なら Karabiner-Elements を再起動: メニューバーの Karabiner アイコン → "Restart Karabiner-Elements" もしくは `osascript -e 'quit app "Karabiner-Elements"' && open -a Karabiner-Elements`)

- [ ] **Step 5: 動作確認 (Caps Lock + Z 同時押し)**

実 Claude Code セッションで何か応答を出してもらってから (Task 6 で state file が更新されている前提):

1. キーボードで Caps Lock を押しながら Z を押す
2. Kyoko の声で直前応答が読まれることを確認
3. 読み上げ中にもう一度 Caps Lock + Z で停止することを確認

Expected: 期待通り再生 ⇄ 停止のトグル。

- [ ] **Step 6: 単独 Caps Lock の挙動が壊れていないか確認**

```bash
# Handy モードに切り替え
voice-switch ja
```

Caps Lock を単独で 1 回押す → Handy の録音トグルが反応することを確認。

```bash
# Typeless モードに切り替え
voice-switch typeless
```

Caps Lock を単独で 1 回押す → Typeless の録音トグル (F18 emit) が反応することを確認。

Expected: いずれも従来通り動作。

- [ ] **Step 7: Commit**

```bash
cd /Users/snakashima/dotfiles
git add karabiner/karabiner.json
git commit -m "feat(karabiner): Caps Lock + Z で voice-out 起動 (single Caps Lock の動作は不変)"
```

---

## Task 9: ドキュメント整備と最終 push

**Files:**
- Modify: `/Users/snakashima/dotfiles/bin/voice-out` (ヘッダコメント整備)
- Optional Modify: `/Users/snakashima/dotfiles/README.md` (使い方 1 セクション)

**Interfaces:**
- Consumes: Task 8 までの全実装
- Produces: bin/voice-out の冒頭コメントが運用者向けに整備されている

- [ ] **Step 1: bin/voice-out のヘッダコメントを整える**

`bin/voice-out` の冒頭コメントを以下に置換 (`#!/bin/bash` 行を残し、その下のコメントブロックを以下に書き換え):

```bash
#!/bin/bash
# voice-out — Claude Code の直前応答を macOS say (Kyoko) で読み上げる。
#
# 通常起動 (Karabiner: Caps Lock + Z 経由):
#   /Users/snakashima/dotfiles/bin/voice-out
#     → ~/.cache/claude-tts.last-transcript から transcript_path を読み、
#       末尾 assistant の text ブロックを sanitize して say に流す。
#
# 手動デバッグ:
#   voice-out --text "..."        渡された text をそのまま (sanitize あり) say
#   voice-out --transcript PATH   指定 transcript JSONL の末尾 assistant を抽出
#
# トグル: 既に say が走っていれば pkill して exit 0 (同じキーで再生/停止)
# 競合: Typeless / Handy 起動中は silent skip (feedback loop 防止)
# 失敗: best-effort、stdout/stderr は静か。CLAUDE_TTS_DEBUG=1 で /tmp/voice-out.log
#
# 環境変数:
#   CLAUDE_TTS_VOICE   default: Kyoko
#   CLAUDE_TTS_RATE    default: 180 wpm
#   CLAUDE_TTS_DEBUG   set to 1 で詳細ログを /tmp/voice-out.log へ
#
# 関連:
#   - claude/hooks/stop.sh : state file (~/.cache/claude-tts.last-transcript) 更新
#   - karabiner/karabiner.json : Caps Lock + Z バインド
#   - test/voice-out.bats : sanitize の自動テスト
#   - docs/superpowers/specs/2026-06-22-claude-tts-design.md : 設計書
```

- [ ] **Step 2: 全体動作を最終 sanity test**

```bash
cd /Users/snakashima/dotfiles
bats test/voice-out.bats
echo '---'
/Users/snakashima/dotfiles/bin/voice-out --text "最終確認テスト"
```

Expected: bats 7/7 ok、Kyoko が「最終確認テスト」と読む。

- [ ] **Step 3: Commit**

```bash
cd /Users/snakashima/dotfiles
git add bin/voice-out
git commit -m "docs(voice-out): ヘッダコメントを運用者向けに整備"
```

- [ ] **Step 4: ここまでの全コミットを push**

```bash
git push origin main
```

Expected: 全 Task の commit が origin に反映される。

---

## Self-Review (Plan 作成者によるチェック結果)

**1. Spec coverage:**
- spec 2 (要件) のすべて → Task 1-7 で実装、Global Constraints に転記済み
- spec 3 (アーキテクチャ) → Task 1-8 で構築
- spec 4 (コンポーネント) → 4.1 bin/voice-out (Task 1-7) / 4.2 stop.sh (Task 6) / 4.3 karabiner.json (Task 8)
- spec 5 (データフロー) → Task 5 (transcript 抽出) + Task 6 (state file) + Task 4 (sanitize)
- spec 6 (エラーハンドリング) → Task 3 (競合), Task 6 (state file 不在), Task 7 (上限), Task 1 のヘルパ (silent fail)
- spec 7 (テスト戦略) → Task 0 (bats), Task 4 (.bats ファイル), 各 Task 末尾の sanity
- spec 8 (リスク) → debug ログ (Task 1, 7) で実機検証する経路を確保
- spec 9 (既存影響) → Task 8 Step 6 で単独 Caps Lock の挙動を verify
- spec 10 (段階分け) → 本 Plan の Task 1-9 と一致

**2. Placeholder scan:** "TBD"/"TODO"/"後で" 等を grep — 該当なし。

**3. Type consistency:**
- 環境変数: `CLAUDE_TTS_VOICE` / `CLAUDE_TTS_RATE` / `CLAUDE_TTS_DEBUG` が全 task で一貫
- ファイルパス: `~/.cache/claude-tts.last-transcript` が stop.sh と voice-out で同一
- 関数名: `sanitize` / `extract_latest_assistant` / `log` が Task 内で参照ズレなし
- jq 抽出式: Task 5 Step 2 (動作確認) と Step 3 (関数本体) で同一クエリ

**4. 補足の構造的注意:**
- Task 4 の bats `load_voice_out()` は `sanitize` 関数のソースコードを抽出して eval。これは sanitize 関数が `bin/voice-out` の `^sanitize()` で始まり次の `^}` で終わる正規構造であることに依存。voice-out で sanitize の前後に他の関数 (log, extract_latest_assistant) がある順序を Task 4-5 で保つこと。
