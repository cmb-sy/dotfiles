---
title: Caps Lock 押下時に意図しない音声入力モードに入る問題
date: 2026-06-23
status: fixed
---

# Caps Lock 押下時に「別のアプリで音声がリアルタイム入力される」問題

## Symptom (症状)

- `voice-switch typeless` で Typeless 派の運用をしているはずなのに、Caps Lock 押下時に意図しない音声入力モードに入る
- `voice-switch status` が `engine = none` を返す状況で発生
- 再発頻度: 「これ多い」(user 報告)

## Root Cause (根本原因)

二段重ねの原因:

### 原因 A: macOS Dictation が ON (`AppleDictationAutoEnable = 1`)

OS 標準の Dictation 機能が有効化されており、何らかのキー入力で音声入力モードに入っていた。Dictation は「フォーカス中のテキスト欄にリアルタイムで文字を流し込む」挙動で、user 報告の「リアルタイム入力」と一致。

確認:
```sh
defaults read com.apple.HIToolbox AppleDictationAutoEnable      # → 1 (ON)
defaults read com.apple.assistant.support 'Dictation Enabled'   # → 1 (ON)
```

### 原因 B: voice-toggle の「Handy も Typeless も不在なら open -a Handy」ロジック

`bin/voice-toggle` は両方不在時に勝手に Handy を起動していた。これは「user は Handy を主に使う」という前提のレガシーロジック。Typeless 派の user にとっては意図しない Handy 起動の温床。

該当箇所 (旧):
```bash
if ! /usr/bin/pgrep -x handy >/dev/null 2>&1; then
  /usr/bin/open -a Handy
  exit 0
fi
```

## Fix (修正)

### Fix A: macOS Dictation を OFF (defaults + launchctl の二段構え)

**重要**: `defaults write` だけだと macOS が daemon 起動時に再 ON にする観測あり (2026-06-24 再発確認)。`launchctl disable` で agent 自体を恒久 disable する必要がある。

```sh
# 1. defaults を OFF
defaults write com.apple.HIToolbox AppleDictationAutoEnable -bool false
defaults write com.apple.assistant.support 'Dictation Enabled' -bool false
killall cfprefsd 2>/dev/null

# 2. 走行中の Dictation プロセスを kill (SIP で bootout は弾かれるが部分停止する)
launchctl bootout gui/$(id -u)/com.apple.DictationIM 2>/dev/null || true
launchctl bootout gui/$(id -u)/com.apple.assistant.dictation 2>/dev/null || true

# 3. 再起動を防ぐため user agent を disable (これは SIP 対象外で permanent)
launchctl disable gui/$(id -u)/com.apple.DictationIM
launchctl disable gui/$(id -u)/com.apple.assistant.dictation
```

**さらに確実にするには macOS GUI でも OFF**: システム設定 → キーボード → 音声入力 → 「音声入力」を OFF。GUI 設定が defaults より priority high で扱われるため、これが最も恒久的。

OS 設定 (`~/Library/Preferences/` 配下) のため git 管理外。マシンセットアップ時に再適用する場合は本ファイルを参照。

### Fix C: voice-out のトリガーを `F1` 単独キーに変更 (2026-06-24 追加)

`Caps Lock + Z` の simultaneous バインドは 2 つの問題を抱えていた:
1. **同時押し threshold の調整が必要** — default 50ms は短く、人間の押下リズムで取りこぼされる
2. **Typeless 競合 check で silent skip** — Caps Lock + Z が正しく発火しても、voice-out が Typeless 起動中を検知して exit 0 してしまい、結果として「何も起こらない」状態に

複合的な簡素化として、トリガーを `F1` 単独キーに変更し、競合 check を削除:

#### Karabiner: `F1 → voice-out`
```json
{
    "description": "F1 → voice-out (直前の Claude 応答を再生/停止トグル)",
    "manipulators": [
        {
            "type": "basic",
            "from": { "key_code": "f1", "modifiers": { "optional": ["any"] } },
            "to": [ { "shell_command": "/Users/snakashima/dotfiles/bin/voice-out" } ]
        }
    ]
}
```

- 単独キーなので simultaneous threshold 不要 → `parameters` ブロックも削除
- Caps Lock 系ルールと完全に独立。並行発火・競合なし
- macOS 標準では F1 = 画面輝度下げ。Karabiner で `f1` を捕まえることでメディアキー機能をオーバーライド

#### voice-out: Typeless / Handy 競合 check 削除

```bash
# 旧: 競合 check で silent skip
if /usr/bin/pgrep -f "/Applications/Typeless.app/Contents/MacOS/" >/dev/null 2>&1; then
  log "Typeless running, skipping to avoid feedback loop"
  exit 0
fi

# 新: Typeless/Handy 起動中でも読み上げ続行
# feedback loop はヘッドホン使用で防ぐ運用に変更
```

**Feedback loop の懸念**: TTS 出力 → スピーカー → マイク → 録音アプリ誤認識のリスクは残るが、Typeless/Handy を使う user は通常ヘッドホン or 静音環境で作業しているため許容範囲。スピーカー出力で feedback loop が観測されたら、TTS 専用の出力デバイス (例: USB ヘッドホン) を選ぶか、再度競合 check を入れる。

### Fix B: voice-toggle の defensive 化 (★ user 判断で revert 済み)

当初は両方不在時に通知 + silent skip にしたが、user 確認の結果「Typeless が起動していない時は Handy を起動してほしい」が意図された動作と判明。Fix A (Dictation OFF) で根本原因が解消されているため、Handy フォールバックは無罪。voice-toggle は元の `open -a Handy` フォールバックロジックに戻した。

採用された最終形 (元のロジック維持):
```bash
if ! /usr/bin/pgrep -x handy >/dev/null 2>&1; then
  /usr/bin/open -a Handy
  exit 0
fi
```

## 再発防止策

- 新規 Mac セットアップ時に `setup/` 系で **defaults + launchctl disable + GUI OFF** の 3 段構えで Dictation を確実に止める (TODO: setup スクリプトに追記検討)
- voice-toggle の Handy フォールバックは意図的に維持。根本原因は OS 側 Dictation だったので、voice-toggle 側の防御策は不要
- Karabiner simultaneous threshold は 200ms を維持 (50ms だと人間の押下リズムで取りこぼす)
- 2026-06-24 の再発で判明: macOS は OS アップデート or daemon 再起動時に Dictation defaults を再 ON にすることがある。launchctl disable と GUI OFF の二重防御が必要

## 関連

- `bin/voice-toggle` (Fix B)
- `bin/voice-switch` (engine 切替の正規経路、変更なし)
- `karabiner/karabiner.json` (Fix C: simultaneous_threshold_milliseconds = 200)
- 既存メモリ `project_voice_input.md`, `project_macos_dictation_must_off.md`
