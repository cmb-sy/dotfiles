# voice-switch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `handy-switch` を `voice-switch` に拡張し、新たに `typeless` サブコマンドで Typeless 音声入力アプリへ切替可能にする。Karabiner / 既存エイリアスとの後方互換を維持する。

**Architecture:** `bin/voice-switch` / `bin/voice-toggle` を新規作成し、`bin/handy-switch` / `bin/handy-toggle` を後方互換 shim に置換する。Handy 関連の `apply-settings.py` / glossary 等は変更しない。Typeless は GUI/クラウド管理のため、外部からは起動・終了のみを行い、設定書換は試みない。

**Tech Stack:** zsh / bash / osascript / pgrep / open / brew (cask) / Karabiner-Elements

**Spec:** `docs/superpowers/specs/2026-06-15-voice-switch-design.md`

---

## 既存ファイル一覧（影響範囲）

| ファイル                                    | 役割                                    | 変更内容                              |
| ------------------------------------------- | --------------------------------------- | ------------------------------------- |
| `bin/handy-switch`                          | Handy 切替本体                          | shim に置換                           |
| `bin/handy-toggle`                          | Karabiner Caps Lock 用 toggle           | shim に置換                           |
| `bin/voice-switch`                          | 新規（handy-switch ロジック + typeless）| 新規作成                              |
| `bin/voice-toggle`                          | 新規（handy-toggle ロジック + 判定）    | 新規作成                              |
| `bin/help_key:142-148`                      | help 文言                               | vs* 主表記、hs* 後方互換注記          |
| `.aliases.sh:151-154`                       | hs* エイリアス                          | vs* 追加、hs* は voice-switch 経由   |
| `handy/apply-settings.py`                   | Handy 設定書換                          | 変更なし                              |
| `karabiner/karabiner.json:24`               | `bin/handy-toggle` を呼ぶ shell_command | 変更なし (shim 経由で voice-toggle へ)|

---

## Task 1: voice-switch 本体を作成し handy-switch を shim 化

**Files:**
- Create: `bin/voice-switch`
- Modify: `bin/handy-switch` (内容を 1 行 shim に置換)

- [ ] **Step 1: voice-switch を新規作成**

`bin/voice-switch` に以下を書く（handy-switch の全機能を移植 + typeless サブコマンドと事前 Typeless quit ロジックを追加）:

```bash
#!/bin/zsh
# Switch the active voice-input engine (Handy or Typeless), anytime.
#
#   voice-switch ja            -> Handy + ollama qwen3:4b (offline; STT locked to ja)
#   voice-switch en            -> Handy + ollama qwen3:4b (offline; STT locked to en)
#   voice-switch cloud [model] -> Handy + Cerebras gpt-oss-120b (STT=auto, bilingual)
#   voice-switch local         -> back-compat alias for `ja`
#   voice-switch typeless      -> Typeless (built-in LLM, GUI-managed). Handy is quit.
#   voice-switch reapply       -> re-run apply with current Handy provider+language
#                                 (no-op + notice if Typeless is the active engine)
#   voice-switch status        -> print active engine + (if Handy) provider/model/language
#
# Handy: settings_store.json を CLI から書き換えるので Quit -> apply -> Relaunch。
# Typeless: 設定は GUI/クラウド管理のため、外側からは起動/終了のみ制御する。
# 両者はマイクとホットキーを取り合うので排他切替。

set -euo pipefail

KEYCHAIN_SVC="handy-cerebras-api-key"
SETTINGS="$HOME/Library/Application Support/com.pais.handy/settings_store.json"
HERE="${0:A:h}"
APPLY="${HERE:h}/handy/apply-settings.py"
TYPELESS_APP="/Applications/Typeless.app"

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
  while /usr/bin/pgrep -x Typeless >/dev/null 2>&1; do
    (( ++n > 50 )) && die "Typeless did not quit within 5s"
    sleep 0.1
  done
}

is_handy_running()    { /usr/bin/pgrep -x handy    >/dev/null 2>&1 }
is_typeless_running() { /usr/bin/pgrep -x Typeless >/dev/null 2>&1 }

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

- [ ] **Step 3: handy-switch を shim に置換**

`bin/handy-switch` の中身を以下に置換:

```bash
#!/bin/zsh
# Back-compat alias: handy-switch was renamed to voice-switch on 2026-06-15.
# This shim keeps existing scripts / muscle memory working.
exec "${0:A:h}/voice-switch" "$@"
```

実行権限はそのまま (元から +x)。

- [ ] **Step 4: 動作確認**

```bash
/Users/snakashima/dotfiles/bin/voice-switch status     # 動くこと
/Users/snakashima/dotfiles/bin/handy-switch status     # voice-switch と同じ出力が出ること (shim 動作)
/Users/snakashima/dotfiles/bin/voice-switch ja         # Handy が JA モードで再起動 (※ ollama 起動済みなら)
```

- [ ] **Step 5: コミット**

```bash
cd /Users/snakashima/dotfiles
git add bin/voice-switch bin/handy-switch
git commit -m "feat(voice-switch): voice-switch を新設し handy-switch を後方互換 shim に置換 (typeless サブコマンド対応)"
```

---

## Task 2: voice-toggle を作成し handy-toggle を shim 化

**Files:**
- Create: `bin/voice-toggle`
- Modify: `bin/handy-toggle` (内容を 1 行 shim に置換)

- [ ] **Step 1: voice-toggle を作成**

`bin/voice-toggle` に以下を書く:

```bash
#!/bin/bash
# Toggle the active voice-input engine's recording, bound to Caps Lock via Karabiner.
#
# - Handy が起動中: handy --toggle-post-process を呼ぶ (既存挙動)
# - Typeless が起動中: no-op (Typeless 側のホットキーで録音、CLI フックなし)
# - どちらも停止: Handy を起動 (録音はしない)
#
# Karabiner runs this in a minimal launchd env, so use absolute paths.

HANDY_BIN="/Applications/Handy.app/Contents/MacOS/handy"

if /usr/bin/pgrep -x Typeless >/dev/null 2>&1; then
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

- [ ] **Step 3: handy-toggle を shim に置換**

```bash
#!/bin/bash
# Back-compat alias: handy-toggle was renamed to voice-toggle on 2026-06-15.
# Karabiner config still calls bin/handy-toggle by path; this shim forwards to voice-toggle.
exec "$(/usr/bin/dirname "$0")/voice-toggle" "$@"
```

- [ ] **Step 4: 動作確認**

```bash
/Users/snakashima/dotfiles/bin/handy-toggle    # 既存 Karabiner 操作と同等に動く (Handy 起動中なら録音トグル)
```

実機で Caps Lock を押して動作確認（Karabiner 経由）。

- [ ] **Step 5: コミット**

```bash
cd /Users/snakashima/dotfiles
git add bin/voice-toggle bin/handy-toggle
git commit -m "feat(voice-toggle): voice-toggle を新設し handy-toggle を後方互換 shim に置換 (Typeless 起動中は no-op)"
```

---

## Task 3: エイリアスと help_key を更新

**Files:**
- Modify: `.aliases.sh:151-154`
- Modify: `bin/help_key:142-148`

- [ ] **Step 1: `.aliases.sh` を更新**

旧定義 (lines 151-154):

```bash
alias hsja='handy-switch ja'
alias hsen='handy-switch en'
alias hscl='handy-switch cloud'
alias hslo='handy-switch local'   # back-compat: same as hsja (local mode is ja-locked)
```

を以下に置換:

```bash
# Voice-switch (engine + mode). Use these going forward.
alias vsja='voice-switch ja'
alias vsen='voice-switch en'
alias vscl='voice-switch cloud'
alias vsty='voice-switch typeless'
alias vslo='voice-switch local'   # back-compat: same as vsja (local mode is ja-locked)

# Back-compat aliases (handy-switch was renamed to voice-switch on 2026-06-15).
alias hsja='voice-switch ja'
alias hsen='voice-switch en'
alias hscl='voice-switch cloud'
alias hslo='voice-switch local'
```

- [ ] **Step 2: `bin/help_key` を更新**

旧 (lines 142-148 周辺):

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
kv "vslo / voice-switch local"     "ja の後方互換エイリアス (vsja と等価)"
kv "voice-switch reapply"          "現在のモードのまま再適用 (Handy 時のみ意味あり)"
kv "voice-switch status"           "現在エンジン + Handy ならモード詳細を表示"
kv "hsja / hsen / hscl / hslo"     "旧名後方互換 (voice-switch 経由で動作)"
```

- [ ] **Step 3: シェルでエイリアスが効くか確認**

```bash
source ~/.aliases.sh && type vsja vsty hsja
# 期待: vsja, vsty, hsja がすべて voice-switch の各サブコマンドに解決される
```

- [ ] **Step 4: コミット**

```bash
cd /Users/snakashima/dotfiles
git add .aliases.sh bin/help_key
git commit -m "feat(voice-switch): vs* エイリアスと help_key 表記を更新 (hs* は後方互換維持)"
```

---

## Task 4: ドキュメント整合（memory + README + Brewfile）

**Files:**
- Modify: `/Users/snakashima/.claude-work/projects/-Users-snakashima-dotfiles/memory/project_voice_input.md`
- Modify: `/Users/snakashima/dotfiles/Brewfile` (typeless cask 追記、存在すれば)
- Modify: `/Users/snakashima/dotfiles/README.md` (handy-switch 言及があれば voice-switch にも触れる)

- [ ] **Step 1: memory を更新**

`project_voice_input.md` の本文を、現在の handy-switch 記述から voice-switch / Typeless にも対応した表記に変更する。具体内容:

- voice-switch (主) / handy-switch (後方互換) の関係
- Handy は CLI 制御 (settings_store.json 書換)、Typeless は GUI/クラウド管理 (起動・終了のみ制御)
- 排他切替 (マイクとホットキー競合のため)

description フィールドは 1 行で「音声入力=Handy+Typeless を voice-switch (旧 handy-switch) で切替。Handy は settings JSON 書換、Typeless は起動/終了のみ。排他」程度に圧縮する。

- [ ] **Step 2: Brewfile に typeless cask 追記**

```bash
grep -n "cask" /Users/snakashima/dotfiles/Brewfile | head -5
```

既存 cask 行のスタイルに合わせて以下を追加 (まだ無ければ):

```ruby
cask "typeless"
```

- [ ] **Step 3: README.md 確認**

```bash
grep -n "handy" /Users/snakashima/dotfiles/README.md 2>/dev/null
```

handy-switch への言及があれば voice-switch に追記または書換。無ければスキップ。

- [ ] **Step 4: コミット**

```bash
cd /Users/snakashima/dotfiles
# memory はリポジトリ外（dotfiles 外）なので別 commit / 別 repo
# dotfiles 側はこう:
git add Brewfile README.md 2>/dev/null || true
git commit -m "docs(voice-switch): Brewfile に typeless cask 追記 / README で voice-switch に言及"
```

memory ファイルはリポジトリ外の場所だが、修正自体は手で実行する（dotfiles の commit 対象外）。

---

## Task 5: e2e 動作確認（ユーザー実行のチェックリスト）

サブエージェント環境では実機の Handy / Typeless / Karabiner / 音声入力をテストできない。下記をユーザーが手動で実施する。

- [ ] **Step 1: Typeless インストール**

```bash
brew install --cask typeless
```

インストール完了後、初回起動して Typeless 内設定で録音ホットキーを設定（Caps Lock とは別キー、例: F5）。

- [ ] **Step 2: voice-switch happy path**

```bash
voice-switch status        # 現在の状態を表示
voice-switch ja            # Handy が JA モードで再起動
voice-switch en            # 同上 EN
voice-switch cloud         # Handy が cloud モード
voice-switch typeless      # Handy quit → Typeless 起動
voice-switch status        # engine = typeless が表示される
voice-switch ja            # Typeless quit → Handy 起動 (JA)
```

- [ ] **Step 3: 旧名 shim**

```bash
handy-switch status        # voice-switch status と同じ
handy-switch typeless      # voice-switch typeless と同じ (Typeless へ切替)
```

- [ ] **Step 4: エイリアス**

```bash
source ~/.aliases.sh
vsty                       # Typeless に切替
vsja                       # JA に切替
hsja                       # 同上 (旧名)
```

- [ ] **Step 5: 異常系**

```bash
# Typeless 未インストール状態を一時再現 (アプリを別の場所に退避してから)
sudo mv /Applications/Typeless.app /Applications/Typeless.app.bak
voice-switch typeless      # エラーで中止、brew インストール案内
sudo mv /Applications/Typeless.app.bak /Applications/Typeless.app
```

- [ ] **Step 6: Karabiner Caps Lock**

- Handy 起動中に Caps Lock → 録音トグル
- Typeless 起動中に Caps Lock → 何も起きない (期待挙動、stdout は見えないが no-op)
- 両方停止状態で Caps Lock → Handy が起動

- [ ] **Step 7: 失敗があれば実装側へフィードバック**

不具合があればこのセッションへ報告。

---

## Self-Review Checklist

- [x] **Spec coverage**: spec 内のすべての要件にタスクが対応している
- [x] **後方互換**: handy-switch / handy-toggle / hs* エイリアス / Karabiner config は変更なしで動作
- [x] **エラーハンドリング**: Typeless 未インストール / quit 失敗を spec 通りに扱う
- [x] **配置一貫**: voice-switch / voice-toggle は handy-switch / handy-toggle と同じ `bin/` に配置
- [x] **Placeholder scan**: TBD / TODO 等の未実装プレースホルダなし
- [x] **シェル構文**: zsh で書く部分 (`voice-switch`) と bash で書く部分 (`voice-toggle`) を明示

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-15-voice-switch.md`. Two execution options:

1. **Subagent-Driven (recommended)** - Fresh subagent per task, review between tasks, fast iteration
2. **Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
