---
title: Handy音声入力 × Teams自動ミュート連携
status: approved
created: 2026-07-07
owner: snakashima
---

# voice-teams-mute 設計書

## 目的・スコープ

会議中に Caps Lock で Handy 音声入力（`bin/voice-toggle` 経由）を使うと、発話が Microsoft Teams の会議マイクにも拾われ、相手に聞こえてしまう。これを防ぐため、Caps Lock による録音開始/終了に連動して Teams のマイクを自動でミュート/アンミュートする。

- 対象アプリ: Microsoft Teams（New Teams、`com.microsoft.teams2` / WebView2 ベース）のみ。Zoom・Google Meet・Slack Huddle は対象外（YAGNI）
- 適用条件: **Teams が実際に会議中（マイク/カメラ画面）のときのみ**。Teams が起動しているだけでは何もしない
- 対象は Handy モードの音声入力のみ（Typeless モードは対象外。Typeless は Karabiner が F18 を直接 emit する経路であり `voice-toggle` を経由しないため）

## 想定ユーザー・運用

| 項目 | 想定 |
| --- | --- |
| 主ユーザー | snakashima（dotfiles のオーナー、macOS） |
| 発生頻度 | Teams 会議中に Caps Lock で口述する場面（頻度は不定期） |
| 許容トレードオフ | Caps Lock 押下のたびに Teams への一瞬のフォーカス切替（ちらつき）が発生することは許容 |

## 前提となる制約（実機調査で判明）

- Teams の `Cmd+Shift+M` はグローバルショートカットではなく、**Teams ウィンドウにフォーカスがある時のみ**動作する。バックグラウンドから発火させる公式手段は無い
- `Cmd+Shift+M` は**トグル**であり、「ミュートにする/解除する」を直接指定するコマンドではない。録音開始時・終了時に単純に1回ずつ送るだけの実装だと、**録音開始前に既に手動でミュート済みだった場合に意図と逆転する**（誤ってアンミュートしてしまう）バグを生む
- Teams の会議中/非会議中を判定する公式 API は無い

## アーキテクチャ / フロー

`bin/voice-toggle` に録音状態を追跡させ、開始/終了の境目で `bin/voice-teams-mute` を呼び出す。

```
Caps Lock 押下 (Handyモード)
  state file 確認
    idle の場合（録音開始）:
      1. voice-teams-mute mute-if-in-call
      2. handy --toggle-post-process
      3. state = recording
    recording の場合（録音終了）:
      1. handy --toggle-post-process
      2. voice-teams-mute restore
      3. state = idle (state file 削除)
```

state file: `~/.cache/dotfiles/voice-recording.state`（`recording` の1行のみ、無ければ idle 扱い）

### `bin/voice-teams-mute` サブコマンド

**`mute-if-in-call`**
1. `pgrep -x MSTeams` で Teams 未起動なら即終了（何もしない）
2. 直前のフォーカスプロセス名を `System Events` で記録
3. Teams をアクティブ化
4. Accessibility 経由で会議中のミュート/アンミュートボタン要素を探索
   - 見つからない（＝会議中でない）→ フォーカスを元に戻して終了。これが fail-safe のデフォルト経路
   - 見つかり、かつ現在「未ミュート」状態 → `Cmd+Shift+M` 送信でミュート化し、`~/.cache/dotfiles/voice-teams-muted-by-us` を作成（自分がミュートした記録）
   - 見つかり、かつ既に「ミュート済み」→ 何もしない（記録ファイルも作らない）
5. 元のフォーカスプロセスに戻す

**`restore`**
1. `~/.cache/dotfiles/voice-teams-muted-by-us` が存在しない → 何もせず終了（会議中でなかった、または元々ミュート済みだったケース）
2. 存在する場合のみ: Teams をアクティブ化 → `Cmd+Shift+M` でアンミュート → フォーカスを元に戻す → 記録ファイルを削除

## 実装フェーズ分割（既知のリスクへの対応）

New Teams は WebView2 ベースであり、ミュートボタンが macOS の Accessibility API 経由で見えるかどうかは**実際の会議中でないと検証できない**。偽の会議を作って検証するのは適切でないため、実装を2段階に分ける。

- **Phase 0（検証）**: 次回の実会議中に、Teams の Accessibility Tree を `System Events` でダンプする使い捨て調査スクリプトを1回実行し、ミュートボタンの実際の識別子（role / description / title 等）を確認する
- **Phase 1（本実装）**: Phase 0 で得た識別子を使って `bin/voice-teams-mute` を実装し、`bin/voice-toggle` に組み込む
  - Phase 0 でボタンが Accessibility 経由で見えないと判明した場合のフォールバック: 会議中判定はウィンドウの存在ベースの簡易判定に切り替え、ミュート操作は状態を読まず盲目的にトグルする簡易版とする（不正確さは残るが実装は成立する）

## エラーハンドリング

| ケース | 挙動 |
| --- | --- |
| Teams 未起動 | `mute-if-in-call` / `restore` とも即終了（何もしない） |
| Accessibility 権限未許可 | AppleScript エラーを `~/.cache/dotfiles/voice-teams-mute.log` に記録し、fail open（録音自体はブロックしない） |
| ミュートボタンが見つからない（非会議中） | 何もせず終了。誤ってフォーカスだけ奪って戻す |
| `restore` 時に Teams が既に終了している | エラーを無視して終了（記録ファイルは削除） |

## スコープ外（YAGNI）

- Zoom / Google Meet / Slack Huddle 等、Teams 以外の会議アプリへの対応
- Typeless モードでの同等機能
- 「会議中かどうか」を音声入力トリガー以外のタイミングでも常時監視する常駐プロセス化
- ミュート操作の視覚的フィードバック通知（まずは無音での自動化を優先）

## テスト方針

Phase 0 はライブ会議でのみ検証可能なため、手動テストのみ。

1. Phase 0: 実会議中に調査スクリプトを実行し、ミュートボタンの Accessibility 識別子をログ出力・確認する
2. Phase 1 実装後、実会議中に Caps Lock で録音開始 → Teams が自動ミュートされることを目視確認
3. 録音終了で Caps Lock を再度押下 → Teams が自動アンミュートされることを確認
4. 会議開始前に手動でミュート済みの状態から Caps Lock 録音 → 録音終了後もミュートのままであること（アンミュートされないこと）を確認
5. Teams 非会議中（起動のみ）に Caps Lock を押下 → フォーカスのちらつきや誤操作が起きないことを確認
6. Teams 未起動状態で Caps Lock を押下 → 通常の Handy 録音のみ動作し、エラーが出ないことを確認
