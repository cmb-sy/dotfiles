---
title: voice-switch — Handy / Typeless 音声入力エンジン切替
status: approved
created: 2026-06-15
owner: snakashima
---

# voice-switch 設計書

## 目的・スコープ

既存 `handy-switch` (Handy の ja / en / cloud 切替) を `voice-switch` にリネームし、別系統の音声入力アプリ Typeless にも切り替えられるようにする。Handy と Typeless の「外部制御モデル」の違いを設計に反映する。

- handy-switch → voice-switch に **完全リネーム**（後方互換は持たない、旧名は削除）
- Handy: 既存ロジック維持（settings_store.json 書換 + Quit/Relaunch）
- Typeless: アプリ起動 / 終了のみ制御（設定は GUI/クラウド管理）
- Handy と Typeless は排他（マイクとホットキー競合のため）
- 影響範囲: Karabiner config の Caps Lock コマンド、シェルエイリアス、help 表記は全て新名に更新する

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
bin/handy-switch      削除 (git rm)
bin/handy-toggle      削除 (git rm)
handy/apply-settings.py  既存のまま (Handy 専用、Typeless は触らない)
handy/glossary.txt       既存のまま
handy/ja_light_tidy.prompt.txt  既存のまま
```

Karabiner config (`karabiner/karabiner.json`) は `bin/handy-toggle` を呼んでいた箇所を `bin/voice-toggle` に書き換える。

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

### Caps Lock の分岐 (Karabiner variable で切替)

Typeless の hotkey 検出は **synthetic key (osascript 経由) を拒否** することが実機検証で判明したため、Typeless モード時は Karabiner の **Virtual HID 経由で F18 を直接 emit** する設計に変更した。

Karabiner Complex Modifications で同一 Caps Lock に 2 ルールを定義し、variable で分岐する:

```
Caps Lock 押下時:
  voice_engine == "typeless"  → Karabiner が Virtual HID 経由で F18 を直接 emit
                                 (Typeless がグローバルホットキー F18 として受信)
  voice_engine != "typeless"  → bin/voice-toggle を shell_command で起動
                                 (Handy --toggle-post-process)
```

`voice_engine` は voice-switch が `karabiner_cli --set-variables` で更新する:

- `voice-switch typeless` → `voice_engine="typeless"`
- `voice-switch ja|en|cloud` → `voice_engine="handy"`

### voice-toggle の挙動

Karabiner が Typeless 経路を吸収するため、voice-toggle は **Handy 専用** に簡素化:

```
1. Typeless プロセスが見つかる (variable 未設定の起動直後など稀なケース) → no-op で終了
2. Handy プロセスが見つかる → handy --toggle-post-process
3. どちらも起動していない → open -a Handy
```

プロセス検出は Handy が `pgrep -x handy`、Typeless は bundle path 経由
`pgrep -f /Applications/Typeless.app/Contents/MacOS/` を使う。

### Typeless 側の F18 登録

Typeless GUI の音声入力ホットキー欄に F18 を **1 回だけ手動登録** する必要がある。
synthetic key (osascript) では登録 UI が反応しないため、Karabiner config を一時的に
「Caps Lock → F18 直接 emit」に切り替えてから物理 Caps Lock を押下し、Virtual HID 経由で
F18 イベントを Typeless GUI に届ける手順を取る。登録後は config を元に戻す。

## エンジン切替時の処理フロー

### `voice-switch ja|en|cloud|local|reapply`
1. `pgrep -x Typeless` で Typeless 起動中なら `osascript -e 'quit app "Typeless"'`
2. 既存ロジック（Handy quit → apply-settings.py → Handy relaunch）

### `voice-switch typeless`
1. `Typeless.app` が `/Applications/` に存在しない → エラーで中止し `brew install --cask typeless` を案内
2. Handy が起動中なら quit
3. `open -a Typeless` で Typeless 起動
4. Typeless プロセスが pgrep -f で見つかるまで最大 15 秒ポーリング待機（Handy の relaunch_handy と同じ idiom）
5. ユーザーに案内: 「Typeless が起動しました。録音はアプリ内設定のホットキー（GUI 設定）で行ってください」

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

`.aliases.sh` の現在の hs* エイリアス 4 行 (`hsja / hsen / hscl / hslo`) は **削除** し、新たに vs* エイリアスを 5 つ追加する:

```
alias vsja='voice-switch ja'
alias vsen='voice-switch en'
alias vscl='voice-switch cloud'
alias vsty='voice-switch typeless'
alias vslo='voice-switch local'
```

`bin/help_key` の hsja/hsen/hscl/hslo 行は削除し、vs* 表記に置き換える:

```
vsja / voice-switch ja          Handy + ローカル(ollama) + STT=ja。日本語専用、最高精度、オフライン
vsen / voice-switch en          Handy + ローカル(ollama) + STT=en。英語専用、最高精度、オフライン
vscl / voice-switch cloud       Handy + Cerebras + STT=auto。bilingual、ネット要、品質高
vsty / voice-switch typeless    Typeless に切替（後処理 LLM 内蔵、翻訳モードあり）
vslo / voice-switch local       ja のエイリアス (vsja と等価)
voice-switch reapply            現在のモードのまま再適用 (Handy 時のみ意味あり)
voice-switch status             現在エンジン + Handy ならモード詳細
```

## ホットキー方針

- Caps Lock (Karabiner 経由) は両エンジン共通の録音トグルとして機能する
- Typeless 録音ホットキーは Typeless GUI で **F18 (key code 79)** に固定設定する。voice-toggle が F18 を emit するので、Typeless はこれをグローバルホットキーとして検知して録音
- voice-toggle の分岐: Typeless 起動中なら F18 emit / Handy 起動中なら handy --toggle-post-process / 両停止なら Handy 起動
- Karabiner config (`karabiner/karabiner.json`) の `shell_command` を `bin/handy-toggle` から `bin/voice-toggle` に書き換える（同一コミットで反映、shim 中継は行わない）

## 関連 skill / 参照

- 旧 `handy-switch` / `handy-toggle`: voice-switch / voice-toggle に置換され削除
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
4. 旧名コマンド `handy-switch` / `handy-toggle` / 旧エイリアス `hsja` 等が **not found** で落ちること（後方互換削除の確認）
5. Typeless 未インストール環境で `voice-switch typeless` → brew インストール案内のエラー
6. `voice-toggle` (Handy 起動中) → 録音トグル
7. `voice-toggle` (Typeless 起動中) → osascript で F18 (key code 79) を emit → Typeless が録音トグル (事前に Typeless GUI で F18 を録音ホットキーに登録要)
8. `voice-toggle` (両方停止) → Handy 起動
9. `vsja / vsen / vscl / vsty / vslo` 各エイリアスが対応する `voice-switch` サブコマンドに解決される
