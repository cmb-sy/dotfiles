---
name: voice-glossary
description: >-
  Handy 音声入力の用語集（誤変換→正表記）にエントリを追加し、Handy 設定へ再適用する。
argument-hint: "[誤変換] [正表記]  (引数なしなら直前の誤変換から推測)"
user-invocable: true
---

Handy 音声入力の後処理プロンプトが参照する用語集 `handy/glossary.txt` に
「誤変換→正表記」のエントリを1件追加し、Handy 設定へ再適用する。

用語集は `apply-settings.py` が読み込み、`ja_light_tidy.prompt.txt` の
`{{GLOSSARY}}` マーカーに「、」連結で差し込む。追加しただけでは反映されず、
`voice-switch <provider>` による quit→apply→relaunch が必要。

---

## 処理フロー

### Step 1: 用語集ファイルの場所を解決

`voice-switch` は dotfiles/bin にあり PATH 上で実行できる。そこから repo を辿る。

```bash
REPO="$(cd "$(dirname "$(command -v voice-switch)")/.." && pwd)"
GLOSSARY="$REPO/handy/glossary.txt"
```

`voice-switch` が見つからない／`$GLOSSARY` が存在しない場合は、その旨を伝えて停止する。

### Step 2: 追加するペア（誤変換 → 正表記）を確定

- **引数が2つ与えられた場合**: 1つ目を「誤変換」、2つ目を「正表記」とする。
- **引数が無い／不足の場合**: 直前の会話で話者が指摘した誤変換から推測する
  （例: ユーザーが「『スキル図』じゃなくて skills」と言った → `スキル図→skills`）。
  推測が曖昧なときは AskUserQuestion で具体候補を提示して確認する。推測で勝手に進めない。

### Step 3: バリデーション

- 「誤変換」「正表記」がどちらも空でないこと。
- どちらにも `→` と改行を含まないこと（用語集の区切り・行構造を壊さないため）。
- `$GLOSSARY` を Read し、左辺（誤変換）が既出かを確認する:
  - **同じ右辺で既出** → 追加不要。その旨を伝えて終了。
  - **異なる右辺で既出** → 上書き更新か中止かを AskUserQuestion で確認する。
  - **未登録** → Step 4 へ。

### Step 4: 用語集へ追記

`$GLOSSARY` の末尾（既存エントリの後）に `誤変換→正表記` を1行追加する。
Read してから Edit で追記する。コメント行・既存エントリの順序は保持する。

### Step 5: 反映の確認（必須）

再適用は Handy を一度終了→再起動するため、ユーザーへの影響がある。
AskUserQuestion で「今すぐ再適用するか／追記のみで後で手動反映するか」を確認する。
**確認なしに `voice-switch` を実行しない。**

### Step 6: 再適用（確認が取れた場合のみ）

`voice-switch reapply` を実行する。これは現在の provider/language を維持したまま
apply-settings.py を再実行するので、`ja`/`en`/`cloud` のどのモードでも安全に使える。
モード判別を skill 側でやる必要はない。

```bash
voice-switch reapply
```

cloud モードの場合 API キーは `voice-switch` が Keychain から読むので、skill 側でキーを扱わない。
再適用後、`voice-switch status` の `prompt = ja_light_tidy` を確認する。

### Step 7: 報告

追加したエントリ・反映の有無を簡潔に報告する。`handy/glossary.txt` は dotfiles の
管理対象なので、コミットするかはユーザーに委ねる（自動コミットしない）。

---

## ルール

1. 推測で誤変換ペアを確定しない。曖昧なら必ず確認する。
2. `voice-switch` による Handy 再起動は、ユーザーの確認を取ってから実行する。
3. 既存エントリと重複させない。重複・競合は Step 3 で解消する。
4. 用語集の行フォーマット `誤変換→正表記` を厳守し、`→`・改行をフィールドに混入させない。
5. 用語集ファイルへの追記以外（プロンプト本文・apply-settings.py）は変更しない。
