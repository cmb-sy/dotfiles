---
title: 企業ファイアウォールのNATタイムアウト対策（TCP keepalive調整）
status: approved
created: 2026-07-09
owner: snakashima
---

# 企業ファイアウォールのNATタイムアウト対策（TCP keepalive調整）設計書

## 目的・スコープ

Claude Code のバックグラウンドサブエージェント実行中に「API Error: Connection closed mid-response」が繰り返し発生する問題を調査し、恒久対策を dotfiles に組み込む。

## 調査で判明した事実

会社ネットワーク（Advantagegroup.co.jp、DNS 10.250.1.35、FortiClient VPN常駐）上で発生。以下を実機調査で確認・除外した:

- システムHTTPプロキシ: 未設定（Wi-Fi/Secure Web Proxyともに無効）
- SSL/TLS介入（企業MITM証明書検査）: なし。`api.anthropic.com` の証明書は正規の Google Trust Services 発行
- VPN(FortiClient)経由の問題: そもそも経由していない。`route get <api.anthropic.comのIP>` で `interface: en0` （通常のWi-Fiインターフェース）が使われることを確認。VPNトンネル(utun0-3)は社内向け(10.250.x.x)のみに使われるsplit-tunnel構成
- MTU/パケットロス: 実経路で1472byte pingが0%ロス・7.7ms、健全
- Wi-Fi切断・ローミング: 直近2時間の `log show` にdisassociation/roamイベントなし
- カスタムAPIエンドポイント/社内AIゲートウェイ: なし。標準の Anthropic API に直接接続

**結論**: 経路そのものは健全。ただし発生タイミングが一貫して長時間（90秒以上）のバックグラウンドサブエージェント実行中だったことから、**企業ファイアウォール/NATのコネクション追跡テーブルのアイドルタイムアウト**が原因と推定される。

## 根本原因のメカニズム

1. NAT/ステートフルファイアウォールは、通過するTCP接続ごとに状態テーブルエントリ（送信元/宛先IP:portの組）を作成し、戻りパケットを許可判定するために使う
2. このエントリには無通信タイムアウトがあり、企業ファイアウォールは接続数上限の制約から比較的短く（数十秒〜数分)設定していることが多い
3. Claude APIのSSEストリーミングは、モデルの思考中やツール実行中に何十秒もパケットが流れない無音区間が発生する
4. 無音区間がタイムアウトを超えると、ファイアウォールは通知なし（RST/FINなし）にエントリを削除する
5. 後続データが来た時、対応エントリが無いため黒板消し的にドロップ、または即時RSTされる
6. クライアント側は「Connection closed mid-response」として観測する

macOSのデフォルト `net.inet.tcp.keepidle` は 7200000ms（2時間）で、企業ファイアウォールのタイムアウトよりずっと長いため、OS標準のkeepaliveは実質機能しない。

## 対策

`net.inet.tcp.keepidle`/`keepintvl`/`keepcnt`/`always_keepalive` を、ファイアウォールのタイムアウトより短い間隔になるようsystem-wideで変更する。

| パラメータ | デフォルト | 変更後 | 理由 |
| --- | --- | --- | --- |
| `net.inet.tcp.keepidle` | 7200000ms(2時間) | 30000ms(30秒) | 無通信30秒でkeepalive開始。ファイアウォールのタイムアウト（数十秒〜数分）より確実に短くする |
| `net.inet.tcp.keepintvl` | 75000ms | 15000ms | 以降15秒間隔で再送 |
| `net.inet.tcp.keepcnt` | 8 | 8 | 変更なし（8回失敗で切断判定） |
| `net.inet.tcp.always_keepalive` | 0 | 1 | アプリがSO_KEEPALIVEを明示指定しなくても全TCP接続に強制適用（Claude Code CLIの実装に依存しないようにする） |

## 実装方式: LaunchDaemon（LaunchAgentではない）

`sysctl -w` の実行にはroot権限が必要。ユーザーのログインセッションで動く LaunchAgent（既存の `macos/system.enviroment.plist` 相当）では root 実行できないため、起動時にrootで1回実行される **LaunchDaemon** を新規導入する。

- 配置場所: `/Library/LaunchDaemons/`（`~/Library/LaunchAgents/` ではない）
- 配布方法: dotfiles内の `macos/com.snakashima.tcp-keepalive-tuning.plist` を **コピー**して root:wheel 所有・644権限で設置する（symlinkは不可 — LaunchDaemonはplistの所有者/書き込み権限を検証し、非rootユーザーが所有・書き込み可能なファイルへのsymlinkは信頼境界を破るため launchd に拒否されるリスクがある）
- 起動時のみ実行（`RunAtLoad: true`、常駐サービスではない）。ログは `/var/log/com.snakashima.tcp-keepalive-tuning.log`

## スコープ外（YAGNI）

- ファイアウォールの実際のタイムアウト値の特定（IT部門のFortinet機器ログが必要で、ユーザー権限では取得不可）
- Anthropic側の対策（クライアント側の制御範囲外）
- 個別アプリケーションごとのkeepalive設定（system-wideで十分と判断）

## 検証方法

1. `sudo sysctl -w net.inet.tcp.keepidle=30000 ...`（4パラメータ）を手動実行し、即時反映を確認
2. plistを `/Library/LaunchDaemons/` に配置・root:wheel 644 設定・`launchctl bootstrap system` でロード
3. `sysctl net.inet.tcp.keepidle` 等で値が保持されていることを確認
4. 再起動後も値が反映されていることを確認（LaunchDaemonのRunAtLoad動作確認）
