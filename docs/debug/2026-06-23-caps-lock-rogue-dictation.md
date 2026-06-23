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

### Fix A: macOS Dictation を OFF (両方の defaults を false に)
```sh
defaults write com.apple.HIToolbox AppleDictationAutoEnable -bool false
defaults write com.apple.assistant.support 'Dictation Enabled' -bool false
killall cfprefsd
```

OS 設定 (`~/Library/Preferences/` 配下) のため git 管理外。マシンセットアップ時に再適用する場合は本ファイルを参照。

### Fix B: voice-toggle の defensive 化
両方不在時に勝手にアプリを起動せず、通知を出して silent skip。voice-switch コマンドでの明示的な engine 選択を促す。

新:
```bash
if ! /usr/bin/pgrep -x handy >/dev/null 2>&1; then
  /usr/bin/osascript -e 'display notification "音声入力アプリが起動していません。voice-switch ja / en / cloud / typeless で起動してください。" with title "voice-toggle"' >/dev/null 2>&1
  exit 0
fi
```

## 再発防止策

- 新規 Mac セットアップ時に `setup/` 系で Dictation を明示的に OFF にする (TODO: setup スクリプトに追記検討)
- voice-toggle のロジックを「自動でアプリを起こさない」原則に統一 (本 fix で完了)

## 関連

- `bin/voice-toggle` (Fix B)
- `bin/voice-switch` (engine 切替の正規経路、変更なし)
- 既存メモリ `project_voice_input.md`
