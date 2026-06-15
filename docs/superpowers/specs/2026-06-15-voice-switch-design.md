---
title: voice-switch — Handy / Typeless 音声入力エンジン切替
status: approved
created: 2026-06-15
owner: snakashima
---

# voice-switch 設計書

## 目的・スコープ

既存 `handy-switch` (Handy の ja / en / cloud 切替) を拡張し、別系統の音声入力アプリ Typeless にも切り替えられるようにする。Handy と Typeless の「外部制御モデル」の違いを設計に反映する。

- handy-switch → voice-switch にリネーム、後方互換エイリアスを残す
- Handy: 既存ロジック維持（settings_store.json 書換 + Quit/Relaunch）
- Typeless: アプリ起動 / 終了のみ制御（設定は GUI/クラウド管理）
- Handy と Typeless は排他（マイクとホットキー競合のため）

## 想定ユーザー・運用

| 項目 | 想定 |
| --- | --- |
| 主ユーザー | snakashima（dotfiles のオーナー、macOS） |
| 起動形態 | 両アプリとも常駐型、グローバルホットキーで録音トグル |
| 切替頻度 | 日内で数回（短時間の口述 = Handy、長文・翻訳 = Typeless など使い分け） |
| インストール | Handy 既導入、Typeless は `brew install --cask typeless` で初回導入（自動化しない、人手） |

## エンジン特性の差

| 観点                    | Handy                                              | Typeless                                  |
| ----------------------- | -------------------------------------------------- | ----------------------------------------- |
| 設定の所在              | `~/Library/Application Support/com.pais.handy/settings_store.json` (ローカル JSON) | アプリ内 GUI、クラウド同期                |
| 後処理 LLM              | 別途 ollama / Cerebras を CLI で繋ぐ               | 内蔵 (filler 除去・tone 適応・翻訳)       |
| 録音トグル CLI          | `Handy.app/Contents/MacOS/handy --toggle-post-process` | 提供なし (ホットキー操作前提)             |
| 言語切替                | ja / en / auto を `settings_store.json` で固定     | GUI 設定、自動判定                        |
| 外部からの細かい制御    | 可能（JSON 書換）                                  | ほぼ不可（CLI フックなし）                |

→ Typeless は「ON/OFF だけ制御、中身は GUI 任せ」という割り切り。

## スクリプト構成

```
bin/voice-switch      新規: エンジン切替の本体
bin/voice-toggle      新規: 録音トグル (現在アクティブなエンジンを判定)
bin/handy-switch      薄い shim: exec voice-switch "$@"  (後方互換)
bin/handy-toggle      薄い shim: exec voice-toggle "$@"  (後方互換)
handy/apply-settings.py  既存のまま (Handy 専用、Typeless は触らない)
handy/glossary.txt       既存のまま
handy/ja_light_tidy.prompt.txt  既存のまま
```

### voice-switch のサブコマンド

```
voice-switch ja        # Handy: ollama qwen3:4b, language=ja
voice-switch en        # Handy: ollama qwen3:4b, language=en
voice-switch cloud [model]  # Handy: Cerebras gpt-oss-120b, language=auto
voice-switch local     # ja の後方互換エイリアス
voice-switch reapply   # 現在のモードのまま再適用 (Handy 時のみ意味あり、Typeless 時は no-op + 通知)
voice-switch status    # 現在アクティブなエンジン + Handy ならモード詳細
voice-switch typeless  # Typeless モードに切替 (Handy quit → Typeless 起動)
```

### voice-toggle の挙動

```
1. pgrep -x Handy が見つかる → handy --toggle-post-process を呼ぶ (既存挙動維持)
2. pgrep -x Typeless が見つかる → Typeless のホットキーが Karabiner Caps Lock に
   バインドできない以上、voice-toggle は no-op で終了 (ユーザーは Typeless 内設定の
   ホットキーで録音する)
3. どちらも起動していない → open -a Handy (既存挙動維持)
```

## エンジン切替時の処理フロー

### `voice-switch ja|en|cloud|local|reapply`
1. `pgrep -x Typeless` で Typeless 起動中なら `osascript -e 'quit app "Typeless"'`
2. 既存ロジック（Handy quit → apply-settings.py → Handy relaunch）

### `voice-switch typeless`
1. `Typeless.app` が `/Applications/` に存在しない → エラーで中止し `brew install --cask typeless` を案内
2. `pgrep -x Handy` で Handy 起動中なら quit
3. `open -a Typeless` で Typeless 起動
4. ユーザーに案内: 「Typeless が起動しました。録音はアプリ内設定のホットキー（GUI 設定）で行ってください」

### `voice-switch status`
1. `pgrep` で両アプリの起動状態を取得
2. Typeless 単独 → `engine = typeless` を表示
3. Handy 単独 → 既存 `print_status` ロジック（provider / model / language / cancel）
4. 両方起動中 → 警告: 排他のはずが両方起動中（人為的に何か起こった状態、ユーザーに修復を案内）
5. 両方停止 → `engine = none` を表示

## エラーハンドリング

| ケース                                       | 挙動                                                                       |
| -------------------------------------------- | -------------------------------------------------------------------------- |
| Typeless 未インストール (voice-switch typeless 実行) | エラー: `brew install --cask typeless` を案内して中止                |
| Typeless quit が完了しない                   | 5 秒待ちで失敗 → エラー (handy-switch quit_handy と同様のループ)            |
| Handy quit が完了しない                      | 既存挙動 (5 秒タイムアウトでエラー)                                        |
| 排他失敗 (両方起動)                          | status で警告、両 quit してから所望のエンジンを起動                        |

## エイリアス更新

`bin/help_key` の現在の記述:

```
hsja / handy-switch ja      ローカル(ollama) + STT=ja。日本語専用、最高精度、オフライン
hsen / handy-switch en      ローカル(ollama) + STT=en。英語専用、最高精度、オフライン
hscl / handy-switch cloud   Cerebras + STT=auto。bilingual、ネット要、品質高
hslo / handy-switch local   ja の後方互換エイリアス (hsja と等価)
handy-switch reapply        現在のモードのまま再適用 (glossary 編集後など)
handy-switch status         現在の provider / model / language を表示
```

を以下に更新（vs* を新規、hs* は後方互換で残す）:

```
vsja / voice-switch ja      Handy + ローカル(ollama) + STT=ja。日本語専用、最高精度、オフライン
vsen / voice-switch en      Handy + ローカル(ollama) + STT=en。英語専用、最高精度、オフライン
vscl / voice-switch cloud   Handy + Cerebras + STT=auto。bilingual、ネット要、品質高
vsty / voice-switch typeless  Typeless に切替（後処理 LLM 内蔵、翻訳モードあり）
voice-switch reapply        現在のモードのまま再適用 (Handy 時のみ意味あり)
voice-switch status         現在エンジン + Handy ならモード詳細
hsja / hsen / hscl / hslo   旧名後方互換 (voice-switch 経由で動作)
```

zsh エイリアス定義の所在を Task 計画で確認・更新する（候補: `zsh/aliases.zsh` 等）。

## ホットキー方針

- Caps Lock (Karabiner 経由) は **Handy 専用**として継続。Typeless 起動時は機能しない（Typeless 側で別キーを設定する）
- Typeless 録音ホットキーは Typeless GUI で設定（推奨: F5 などのファンクションキー、Caps Lock との競合を避ける）
- voice-toggle は「現在 Handy が走っていれば handy --toggle-post-process、Typeless が走っていれば no-op、何も走っていなければ Handy を起動」というシンプルな分岐

## 関連 skill / 参照

- 既存 `handy-switch`: 現状の bash zsh script。voice-switch のベース
- 既存 `handy-toggle`: Karabiner から呼ばれる Caps Lock 用 toggle
- `handy/apply-settings.py`: Handy の settings_store.json 書換ロジック（変更なし）
- Typeless 公式: https://typeless.com/

## スコープ外（YAGNI）

- Typeless 側 CLI ホック（公式 API なし、回避策の AppleScript scripting も将来検討事項）
- Typeless の言語・モデル・ホットキー設定書換（GUI/クラウド管理のため）
- Karabiner config の自動書換（音声切替に伴うキー再割当）
- Typeless 内の翻訳モード切替の CLI ラッピング
- Typeless のユーザー辞書同期（クラウド側で完結）

## テスト方針

すべて手動チェック。

1. `voice-switch ja` 実行 → Handy が再起動し、provider=ollama / language=ja で status 表示
2. `voice-switch typeless` 実行 → Handy が quit、Typeless が起動。status で `engine = typeless`
3. `voice-switch ja` (typeless モード中) → Typeless quit → Handy 起動
4. `handy-switch ja` (旧名) → voice-switch ja と同じ挙動（shim 動作確認）
5. Typeless 未インストール環境で `voice-switch typeless` → brew インストール案内のエラー
6. `voice-toggle` (Handy 起動中) → 録音トグル
7. `voice-toggle` (Typeless 起動中) → no-op、stdout に説明を出す
8. `voice-toggle` (両方停止) → Handy 起動
9. `hsja` `vsja` 両エイリアスが期待通り動作
