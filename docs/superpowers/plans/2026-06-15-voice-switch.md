# voice-switch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `handy-switch` を `voice-switch` に完全リネームし、新たに `typeless` サブコマンドで Typeless 音声入力アプリへ切替可能にする。後方互換は持たない（旧名 handy-switch / handy-toggle / hs* エイリアスは削除、Karabiner config も新名に書き換える）。

**Architecture:** `bin/voice-switch` / `bin/voice-toggle` を新規作成し、`bin/handy-switch` / `bin/handy-toggle` は `git rm` で削除。Karabiner config の Caps Lock コマンドを `bin/voice-toggle` に書き換える。Typeless は GUI/クラウド管理のため、外側からは起動・終了のみで設定書換は試みない。Typeless プロセス検出は bundle path 経由 (`pgrep -f /Applications/Typeless.app/Contents/MacOS/`) で行う（Electron 系の binary 名揺れに耐える）。

**Tech Stack:** zsh / bash / osascript / pgrep / open / brew (cask) / Karabiner-Elements

**Spec:** `docs/superpowers/specs/2026-06-15-voice-switch-design.md`

---

## 影響範囲

| ファイル                                    | 役割                                    | 変更内容                                  |
| ------------------------------------------- | --------------------------------------- | ----------------------------------------- |
| `bin/handy-switch`                          | Handy 切替本体（旧）                    | **git rm で削除**                         |
| `bin/handy-toggle`                          | Karabiner Caps Lock 用 toggle（旧）     | **git rm で削除**                         |
| `bin/voice-switch`                          | 新規（handy-switch ロジック + typeless）| 新規作成                                  |
| `bin/voice-toggle`                          | 新規（handy-toggle ロジック + 判定）    | 新規作成                                  |
| `bin/help_key` (around L142-148)            | help 文言                               | hs* 4 行を削除、vs* 5 行と新説明に置換    |
| `.aliases.sh` (around L151-154)             | hs* エイリアス                          | hs* 4 行を削除、vs* 5 行に置換            |
| `karabiner/karabiner.json` (L24)            | Caps Lock の shell_command              | `bin/handy-toggle` → `bin/voice-toggle`   |
| `handy/apply-settings.py`                   | Handy 設定書換                          | 変更なし                                  |

---

## Task 1: voice-switch 本体を作成し、handy-switch を削除

**Files:**
- Create: `bin/voice-switch`
- Delete: `bin/handy-switch`

- [ ] **Step 1: voice-switch を作成**

`bin/voice-switch` に以下を書く（spec の処理ルールを反映、Typeless 検出は bundle path、起動完了待ち付き）:

```bash
#!/bin/zsh
# Switch the active voice-input engine (Handy or Typeless), anytime.
#
#   voice-switch ja            -> Handy + ollama qwen3:4b (offline; STT locked to ja)
#   voice-switch en            -> Handy + ollama qwen3:4b (offline; STT locked to en)
#   voice-switch cloud [model] -> Handy + Cerebras gpt-oss-120b (STT=auto, bilingual)
#   voice-switch local         -> alias for `ja`
#   voice-switch typeless      -> Typeless (built-in LLM, GUI-managed). Handy is quit.
#   voice-switch reapply       -> re-run apply with current Handy provider+language
#                                 (no-op + notice if Typeless is the active engine)
#   voice-switch status        -> print active engine + (if Handy) provider/model/language
#
# Handy: settings_store.json を CLI から書き換えるので Quit -> apply -> Relaunch。
# Typeless: 設定は GUI/クラウド管理のため、外側からは起動/終了のみ制御する。
# 両者はマイクとホットキーを取り合うので排他切替。
#
# Typeless の binary 名は Electron 系で揺れる可能性があるため、bundle path 経由
# (pgrep -f /Applications/Typeless.app/Contents/MacOS/) で検出する。

set -euo pipefail

KEYCHAIN_SVC="handy-cerebras-api-key"
SETTINGS="$HOME/Library/Application Support/com.pais.handy/settings_store.json"
HERE="${0:A:h}"
APPLY="${HERE:h}/handy/apply-settings.py"
TYPELESS_APP="/Applications/Typeless.app"
TYPELESS_BIN_DIR="$TYPELESS_APP/Contents/MacOS/"

die() { print -u2 "voice-switch: $*"; exit 1 }

quit_handy() {
  /usr/bin/osascript -e 'quit app "Handy"' >/dev/null 2>&1 || true
  local n=0
  while /usr/bin/pgrep -x handy >/dev/null 2>&1; do
    (( ++n > 50 )) && die "Handy did not quit within 5s"
    sleep 0.1
  done
}

relaunch_handy() {
  local n=0
  until /usr/bin/pgrep -x handy >/dev/null 2>&1; do
    (( n % 15 == 0 )) && { /usr/bin/open -a Handy >/dev/null 2>&1 || true; }
    (( ++n > 75 )) && { print -u2 "voice-switch: Handy did not relaunch in ~15s; run 'open -a Handy' manually"; break; }
    sleep 0.2
  done
}

quit_typeless() {
  /usr/bin/osascript -e 'quit app "Typeless"' >/dev/null 2>&1 || true
  local n=0
  while /usr/bin/pgrep -f "$TYPELESS_BIN_DIR" >/dev/null 2>&1; do
    (( ++n > 50 )) && die "Typeless did not quit within 5s"
    sleep 0.1
  done
}

wait_typeless_running() {
  local n=0
  until /usr/bin/pgrep -f "$TYPELESS_BIN_DIR" >/dev/null 2>&1; do
    (( ++n > 75 )) && { print -u2 "voice-switch: Typeless did not start in ~15s; run 'open -a Typeless' manually"; break; }
    sleep 0.2
  done
}

is_handy_running()    { /usr/bin/pgrep -x handy >/dev/null 2>&1 }
is_typeless_running() { /usr/bin/pgrep -f "$TYPELESS_BIN_DIR" >/dev/null 2>&1 }

ensure_handy_active() {
  # Switching to a Handy mode: make sure Typeless is not holding the mic/hotkeys.
  is_typeless_running && quit_typeless
}

print_status() {
  if is_typeless_running && is_handy_running; then
    print "engine = both (unexpected; please quit one)"
    return
  fi
  if is_typeless_running; then
    print "engine = typeless"
    print "(settings: GUI / cloud-managed by Typeless)"
    return
  fi
  if ! is_handy_running; then
    print "engine = none"
    return
  fi
  print "engine = handy"
  [[ -f "$SETTINGS" ]] || die "settings not found: $SETTINGS"
  /usr/bin/python3 - "$SETTINGS" <<'PY'
import json, sys
s = json.load(open(sys.argv[1])).get("settings", {})
pid = s.get("post_process_provider_id")
print(f"provider = {pid}")
print(f"model    = {s.get('post_process_models', {}).get(pid, '')}")
print(f"language = {s.get('selected_language')}")
print(f"enabled  = {s.get('post_process_enabled')}")
print(f"prompt   = {s.get('post_process_selected_prompt_id')}")
print(f"cancel   = {s.get('bindings', {}).get('cancel', {}).get('current_binding')}")
PY
}

[[ -f "$APPLY" ]] || die "applier not found: $APPLY"

apply_cloud() {
  local lang="$1" model_arg="${2:-}"
  local key
  key="$(/usr/bin/security find-generic-password -s "$KEYCHAIN_SVC" -w 2>/dev/null || true)"
  [[ -n "$key" ]] || die "no Cerebras key in Keychain. Add it once:
  security add-generic-password -s $KEYCHAIN_SVC -a \"\$USER\" -w \"<KEY>\""
  ensure_handy_active
  quit_handy
  if [[ -n "$model_arg" ]]; then
    CEREBRAS_API_KEY="$key" /usr/bin/python3 "$APPLY" --provider cloud --language "$lang" --model "$model_arg"
  else
    CEREBRAS_API_KEY="$key" /usr/bin/python3 "$APPLY" --provider cloud --language "$lang"
  fi
  relaunch_handy
}

apply_local() {
  local lang="$1"
  ensure_handy_active
  quit_handy
  /usr/bin/python3 "$APPLY" --provider local --language "$lang"
  relaunch_handy
}

apply_typeless() {
  [[ -d "$TYPELESS_APP" ]] || die "Typeless.app not found at $TYPELESS_APP. Install it once:
  brew install --cask typeless"
  is_handy_running && quit_handy
  /usr/bin/open -a Typeless
  wait_typeless_running
  print -r -- "-> TYPELESS (built-in LLM). 録音は Typeless のアプリ内ホットキー設定で行ってください。"
}

case "${1:-status}" in
  status)
    print_status
    ;;
  ja|local)
    apply_local ja
    print -r -- "-> JA (Handy + ollama qwen3:4b, language=ja). Offline; max Japanese accuracy."
    ;;
  en)
    apply_local en
    print -r -- "-> EN (Handy + ollama qwen3:4b, language=en). Offline; max English accuracy."
    ;;
  cloud)
    apply_cloud auto "${2:-}"
    print -r -- "-> CLOUD (Handy + Cerebras, language=auto). Bilingual; text sent to US, no retention/training."
    ;;
  typeless)
    apply_typeless
    ;;
  reapply)
    if is_typeless_running; then
      print -r -- "voice-switch: 現在 Typeless モードのため reapply は不要 (設定は GUI 管理)。"
      exit 0
    fi
    cur="$(/usr/bin/python3 - "$SETTINGS" <<'PY'
import json, sys
s = json.load(open(sys.argv[1])).get("settings", {})
print(f"{s.get('post_process_provider_id','')} {s.get('selected_language','')}")
PY
)"
    cur_provider="${cur%% *}"
    cur_language="${cur##* }"
    [[ -n "$cur_provider" && -n "$cur_language" ]] || die "could not read current provider/language from settings"
    if [[ "$cur_provider" == "cerebras" ]]; then
      apply_cloud "$cur_language"
    else
      apply_local "$cur_language"
    fi
    print -r -- "-> reapplied provider=$cur_provider language=$cur_language"
    ;;
  *)
    die "usage: voice-switch [ja | en | cloud [model] | local | typeless | reapply | status]"
    ;;
esac
```

- [ ] **Step 2: 実行権限付与**

```bash
chmod +x /Users/snakashima/dotfiles/bin/voice-switch
```

- [ ] **Step 3: handy-switch を削除**

```bash
git rm /Users/snakashima/dotfiles/bin/handy-switch
```

- [ ] **Step 4: 構文チェック**

```bash
zsh -n /Users/snakashima/dotfiles/bin/voice-switch    # exit 0 を期待
```

破壊的なテスト (`voice-switch ja` 等で Handy を再起動) は行わず、syntax のみ。

- [ ] **Step 5: コミット**

```bash
cd /Users/snakashima/dotfiles
git add bin/voice-switch
git commit -m "feat(voice-switch): voice-switch を新設 (handy-switch を完全置換、typeless 対応、bundle path 検出)"
```

---

## Task 2: voice-toggle を作成し、handy-toggle を削除 + Karabiner config を更新

**Files:**
- Create: `bin/voice-toggle`
- Delete: `bin/handy-toggle`
- Modify: `karabiner/karabiner.json` (L24, shell_command の path を書換)

- [ ] **Step 1: voice-toggle を作成**

```bash
#!/bin/bash
# Toggle the active voice-input engine's recording, bound to Caps Lock via Karabiner.
#
# - Typeless が起動中 (bundle path で検出): no-op (Typeless 側のホットキーで録音、CLI フックなし)
# - Handy が起動中: handy --toggle-post-process を呼ぶ
# - どちらも停止: Handy を起動 (録音はしない)
#
# Karabiner runs this in a minimal launchd env, so use absolute paths.

HANDY_BIN="/Applications/Handy.app/Contents/MacOS/handy"
TYPELESS_BIN_DIR="/Applications/Typeless.app/Contents/MacOS/"

if /usr/bin/pgrep -f "$TYPELESS_BIN_DIR" >/dev/null 2>&1; then
  # Typeless is active: recording is driven by Typeless's own in-app hotkey.
  exit 0
fi

if ! /usr/bin/pgrep -x handy >/dev/null 2>&1; then
  /usr/bin/open -a Handy
  exit 0
fi

exec "$HANDY_BIN" --toggle-post-process
```

- [ ] **Step 2: 実行権限付与**

```bash
chmod +x /Users/snakashima/dotfiles/bin/voice-toggle
```

- [ ] **Step 3: handy-toggle を削除**

```bash
git rm /Users/snakashima/dotfiles/bin/handy-toggle
```

- [ ] **Step 4: Karabiner config の path を書換**

`karabiner/karabiner.json` の以下の行 (L24 付近):

```json
{ "shell_command": "/Users/snakashima/dotfiles/bin/handy-toggle" }
```

を

```json
{ "shell_command": "/Users/snakashima/dotfiles/bin/voice-toggle" }
```

に置換。description フィールド (L15 付近、`bin/handy-toggle` を含む) も同様に書き換える。

- [ ] **Step 5: 構文チェック**

```bash
bash -n /Users/snakashima/dotfiles/bin/voice-toggle    # exit 0 を期待
/usr/bin/python3 -c 'import json; json.load(open("/Users/snakashima/dotfiles/karabiner/karabiner.json"))'   # JSON 構文 OK
```

- [ ] **Step 6: コミット**

```bash
cd /Users/snakashima/dotfiles
git add bin/voice-toggle karabiner/karabiner.json
git commit -m "feat(voice-toggle): voice-toggle を新設し handy-toggle 削除、Karabiner config を新パスに書換"
```

---

## Task 3: .aliases.sh + bin/help_key を更新

**Files:**
- Modify: `.aliases.sh` (L151-154 周辺)
- Modify: `bin/help_key` (L142-148 周辺)

- [ ] **Step 1: `.aliases.sh` を更新**

旧 (L151-154):

```bash
alias hsja='handy-switch ja'
alias hsen='handy-switch en'
alias hscl='handy-switch cloud'
alias hslo='handy-switch local'   # back-compat: same as hsja (local mode is ja-locked)
```

を以下に置換:

```bash
alias vsja='voice-switch ja'
alias vsen='voice-switch en'
alias vscl='voice-switch cloud'
alias vsty='voice-switch typeless'
alias vslo='voice-switch local'   # same as vsja (local mode is ja-locked)
```

- [ ] **Step 2: `bin/help_key` を更新**

旧 (L142-147 周辺):

```
kv "hsja / handy-switch ja"      "ローカル(ollama) + STT=ja。日本語専用、最高精度、オフライン"
kv "hsen / handy-switch en"      "ローカル(ollama) + STT=en。英語専用、最高精度、オフライン"
kv "hscl / handy-switch cloud"   "Cerebras + STT=auto。bilingual、ネット要、品質高"
kv "hslo / handy-switch local"   "ja の後方互換エイリアス (hsja と等価)"
kv "handy-switch reapply"        "現在のモードのまま再適用 (glossary 編集後など)"
kv "handy-switch status"         "現在の provider / model / language を表示"
```

を以下に置換:

```
kv "vsja / voice-switch ja"        "Handy + ローカル(ollama) + STT=ja。日本語専用、最高精度、オフライン"
kv "vsen / voice-switch en"        "Handy + ローカル(ollama) + STT=en。英語専用、最高精度、オフライン"
kv "vscl / voice-switch cloud"     "Handy + Cerebras + STT=auto。bilingual、ネット要、品質高"
kv "vsty / voice-switch typeless"  "Typeless に切替 (後処理 LLM 内蔵、翻訳モードあり)"
kv "vslo / voice-switch local"     "ja のエイリアス (vsja と等価)"
kv "voice-switch reapply"          "現在のモードのまま再適用 (Handy 時のみ意味あり)"
kv "voice-switch status"           "現在エンジン + Handy ならモード詳細を表示"
```

- [ ] **Step 3: シェルでエイリアスが効くか確認**

```bash
zsh -i -c 'type vsja vsty 2>&1; type hsja 2>&1 | head -1'
# Expected: vsja, vsty が voice-switch ... に解決される
# Expected: hsja は "not found" 系のエラー (後方互換削除済み)
```

- [ ] **Step 4: コミット**

```bash
cd /Users/snakashima/dotfiles
git add .aliases.sh bin/help_key
git commit -m "feat(voice-switch): vs* エイリアスと help_key 表記を導入 (hs* は削除)"
```

---

## Task 4: ドキュメント整合（memory + Brewfile + README）

**Files:**
- Modify: `/Users/snakashima/.claude-work/projects/-Users-snakashima-dotfiles/memory/project_voice_input.md` (dotfiles リポジトリ外)
- Modify: `/Users/snakashima/dotfiles/Brewfile` (typeless cask 追記)
- Modify: `/Users/snakashima/dotfiles/README.md` (handy-switch 言及があれば voice-switch に置換)

- [ ] **Step 1: memory 更新**

`project_voice_input.md` を Read してから、本文と description フィールドを以下方針で書き換える:

- handy-switch / handy-toggle は削除済みであることを明記
- voice-switch / voice-toggle が新名
- Handy = CLI 制御 (settings JSON 書換)、Typeless = GUI/クラウド管理 (起動/終了のみ)
- 排他切替（マイクとホットキー競合）
- Typeless プロセス検出は bundle path 経由
- description は 1 行で「音声入力=Handy+Typeless を voice-switch で切替。Handy は settings JSON 書換、Typeless は起動/終了のみ。排他」程度に圧縮

- [ ] **Step 2: Brewfile に typeless cask 追記**

```bash
grep -n "^cask" /Users/snakashima/dotfiles/Brewfile | head -3
```

既存 cask 行と同じスタイルで `cask "typeless"` を追加（無ければ）。

- [ ] **Step 3: README.md 確認**

```bash
grep -n "handy" /Users/snakashima/dotfiles/README.md 2>/dev/null
```

handy-switch / handy-toggle への言及があれば voice-switch / voice-toggle に書換。無ければスキップ。

- [ ] **Step 4: コミット**

```bash
cd /Users/snakashima/dotfiles
git add Brewfile README.md 2>/dev/null
git diff --cached --stat
git commit -m "docs(voice-switch): Brewfile に typeless cask 追記 / README で voice-switch に言及" || echo "nothing to commit"
```

memory ファイルはリポジトリ外なので別途修正のみ（dotfiles の commit には含めない）。

---

## Task 5: e2e 動作確認（ユーザー実行のチェックリスト）

サブエージェント環境では実機の Handy / Typeless / Karabiner / 音声入力をテストできない。下記をユーザーが手動で実施する。

- [ ] **Step 1: Typeless インストールと binary 名確認**

```bash
brew install --cask typeless
ls /Applications/Typeless.app/Contents/MacOS/    # binary 名を確認 (pgrep -x で使うなら実名を pin down する判断材料)
```

bundle path 経由検出 (`pgrep -f`) を採用しているため、binary 名が何であっても動作する。

初回起動して Typeless 内設定で録音ホットキーを設定（Caps Lock とは別キー、例: F5）。

- [ ] **Step 2: voice-switch happy path**

```bash
voice-switch status        # 現在の状態を表示
voice-switch ja            # Handy が JA モードで再起動
voice-switch en            # 同上 EN
voice-switch cloud         # Handy が cloud モード
voice-switch typeless      # Handy quit → Typeless 起動 (起動完了待ち付き)
voice-switch status        # engine = typeless が表示される
voice-switch ja            # Typeless quit → Handy 起動 (JA)
```

- [ ] **Step 3: 旧名コマンドが消えていること**

```bash
which handy-switch          # → not found
which handy-toggle          # → not found
type hsja 2>&1              # → not found
```

- [ ] **Step 4: 新エイリアス**

```bash
source ~/.aliases.sh
vsty                       # Typeless に切替
vsja                       # JA に切替
```

- [ ] **Step 5: 異常系**

```bash
# Typeless 未インストール状態を一時再現 (アプリを別の場所に退避)
sudo mv /Applications/Typeless.app /Applications/Typeless.app.bak
voice-switch typeless      # エラーで中止、brew インストール案内
sudo mv /Applications/Typeless.app.bak /Applications/Typeless.app
```

- [ ] **Step 6: Karabiner Caps Lock**

- Handy 起動中に Caps Lock → 録音トグル
- Typeless 起動中に Caps Lock → no-op
- 両方停止状態で Caps Lock → Handy が起動
- Karabiner-Elements の Preferences で Complex Modifications ルールが正しく `bin/voice-toggle` を呼ぶ設定になっていること

- [ ] **Step 7: 失敗があれば実装側へフィードバック**

不具合があればこのセッションへ報告。

---

## Self-Review Checklist

- [x] **Spec coverage**: spec 内のすべての要件にタスクが対応している
- [x] **後方互換削除**: handy-switch / handy-toggle / hs* alias 完全削除、Karabiner config 書換
- [x] **Typeless 検出ロバスト化**: bundle path 経由で binary 名揺れに耐える
- [x] **起動完了待ち**: apply_typeless で wait_typeless_running 追加
- [x] **エラーハンドリング**: Typeless 未インストール / quit 失敗を spec 通りに扱う
- [x] **配置一貫**: voice-switch / voice-toggle は `bin/` に配置
- [x] **Placeholder scan**: TBD / TODO 等の未実装プレースホルダなし
- [x] **シェル構文**: zsh (`voice-switch`) と bash (`voice-toggle`) を明示

## Execution Handoff

Subagent-Driven で実行中。
