# OCI 無料枠 Claude 常駐サーバー 設計書

- 日付: 2026-07-11
- ステータス: 承認済み（実装計画未着手）

## 背景と目的

Mac の電源状態と無関係に、どこからでも繋げる常設の Claude Code 作業環境が欲しい。
Oracle Cloud Infrastructure (OCI) の Always Free 枠に Linux サーバーを 1 台常駐させ、
SSH + tmux 上で Claude Code を動かす。構築手順・設定はこの dotfiles リポジトリで管理し、
サーバーが消えても 30 分以内に同じ環境を再構築できる状態を保つ。

**用途**: 24/7 開発セッション（Tailscale 経由で SSH + tmux に attach、長時間の autonomous ジョブを投げっぱなしにする）。

**扱う対象**: 個人 Anthropic アカウントと個人 GitHub リポジトリのみ。
会社アカウント・会社リポジトリ・業務データは一切持ち込まない。

## 前提となる制約（2026-07 時点）

- 2026-06-15 に Always Free の Ampere A1 枠が 4 OCPU/24GB から **2 OCPU/12GB に半減**した
  （純無料アカウント対象。[InfoQ 報道](https://www.infoq.com/news/2026/07/oracle-cloud-free-tier-limits/)）。
- アイドルインスタンスは回収される: 7 日間の 95 パーセンタイルで CPU・ネットワーク・メモリ
  利用率がすべて閾値（20%）未満だと回収対象
  （[Oracle 公式](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm)）。
- Always Free コンピュートは**ホームリージョンでのみ**作成可能。ホームリージョンは
  アカウント作成後に変更できない。
- A1 の無料枠は容量不足（out of capacity）で作成に失敗することがある。
- Pay As You Go 昇格でこれらの制約は大幅に緩和されるが、本設計では**クレカ登録なしの
  完全 $0 運用**を優先し、純無料アカウントで進める（検討経緯は付録参照）。

## アーキテクチャ

```
[Mac / スマホ] ──Tailscale(tailnet)──▶ [OCI A1.Flex インスタンス]
                                         Ubuntu 24.04 arm64
                                         2 OCPU / 12GB / boot 100GB
                                         inbound 全閉じ（Tailscale outbound のみ）
                                         └─ tmux (systemd user service で常設)
                                             └─ claude (個人アカウント, setup-token 認証)
```

- **リージョン**: ap-tokyo-1（ホームリージョン）。「Out of capacity」時は時間帯を変えて
  手動再試行する（README §2 に記載。CLI リトライスクリプトは必要になった時点で追加 — YAGNI）。
- **ネットワーク**: VCN の security list は inbound を一切開けない。到達手段は
  Tailscale のみ（NAT 越えは outbound で成立する）。公開ポートゼロ。
- **ストレージ**: ブートボリューム 100GB。無料枠の volume backup（5 世代）で週次バックアップ。

## dotfiles への変更

```
server/
├── README.md                # 再構築ランブック（アカウント作成〜復旧まで、目標 30 分）
│                            # ※当初案 docs/server-setup.md から変更: docs/ は gitignore
│                            #   （ローカル専用）のため、GitHub 単体で読める server/ 配下に置く
├── cloud-init.yaml          # apt 基礎 + Tailscale install +
│                            #   `tailscale up --authkey={{TAILSCALE_AUTH_KEY}} --ssh` + dotfiles clone。
│                            #   ※当初案「bootstrap で対話 tailscale up」から変更: inbound 全閉じだと
│                            #   初回 SSH が成立しない鶏卵問題があるため、作成時に使い捨てキー
│                            #   （単回使用・期限付き・事前承認）を placeholder へ手元置換して貼る
├── install.zsh              # 非対話 apt インストーラ（setup/install.zsh が Linux 検出時に exec 委譲）
├── bootstrap.zsh            # 初回 SSH 後に手動実行（--dry-run あり・冪等）。対話は
│                            #   claude の /login（setup-token は credentials を保存しないため不採用）
│                            #   と gh auth login の 2 つ。値のハードコードなし
├── packages.txt             # apt パッケージ（zsh, tmux, git, fzf, ripgrep, stress-ng 等）
├── tmux.service             # tmux 常設の systemd user unit
├── keepalive.service        # 回収対策の負荷生成（下記）
└── keepalive.timer
```

- `setup/install.zsh` に OS 判定を追加し、Linux では Brewfile をスキップして
  `server/packages.txt` + claude 公式インストーラで構成する（mise は不要と判断し導入せず）。
- **Claude 設定はサブセットのみ**持ち込む: グローバル CLAUDE.md の symlink のみ（settings.json は
  持ち込まずデフォルトで運用）。skills / hooks 群は macOS 前提が混ざるため持ち込まない。

## idle 回収対策（keep-alive）

回収条件は「7 日間の 95 パーセンタイルで CPU・ネットワーク・メモリがすべて 20% 未満」の
AND 条件のため、**CPU だけ閾値を超えさせれば回収対象から外れる**。

- 95 パーセンタイルが 20% 以上になる条件 = 全時間の 5% 以上（週 8.4 時間以上）で
  CPU 利用率 20% 超え。
- systemd timer で毎日 2 時間、`stress-ng --cpu 1 --cpu-load 60`（2 OCPU に対し全体
  約 30%）を実行する。週 14 時間 > 8.4 時間でマージン確保。
- 実際の Claude ジョブや将来の定期タスクが十分な負荷を出す場合、合成負荷は縮小してよい。

## secrets 境界（public リポジトリの規律）

| リポジトリに置く | 置かない（手元・サーバーのみ） |
|---|---|
| cloud-init テンプレ（placeholder のみ） | テナンシー/コンパートメント OCID |
| bootstrap/keep-alive スクリプト | インスタンスのパブリック IP |
| packages.txt、ランブック | Tailscale auth key、Anthropic token |
| | SSH 鍵、gh 認証情報 |

既存の pii-guard フックを検知網として利用する。ランブック内の実値は例示用
placeholder（`<tenancy-ocid>` 等）で書く。

## 運用方針（回収・BAN を前提にした設計）

- 作業成果は常に git push で外部化する。サーバー上にしか無い状態を作らない。
- サーバーは「いつ消えても作り直せる家畜」として扱う。復旧はランブック 1 本で完結させる。
- 無料アカウントの突然の停止事例が報告されているため、サーバーを唯一の作業環境にしない。

## 明示的な非対応（YAGNI）

- Terraform 等の IaC ツール導入（単一インスタンス・一度きりの作成には過剰）
- Slack bot / webhook 受信（今回の用途外）
- 会社アカウント・会社リポジトリの取り扱い
- AMD micro (1GB RAM) へのフォールバック（Claude Code の実行には非現実的）
- clp/clw 二重アカウント構成のサーバーへの移植

## 検証方法

1. **bootstrap の冪等性**: `bootstrap.zsh` を 2 回実行しても壊れないこと。
2. **再構築テスト**: インスタンスを一度 terminate → ランブックだけを見て 30 分以内に
   tmux + claude が使える状態まで復元できること（これが本設計の受け入れ試験）。
3. **keep-alive 検証**: 導入 1 週間後に OCI コンソールのメトリクスで CPU 95 パーセンタイル
   が 20% を超えていることを確認。
4. **公開安全性**: `server/`（README 含む）に OCID・IP・トークンが含まれないことを
   `test/server.bats` の秘密スキャンで機械検証（+ pii-guard、push 前の手動確認）。

## 付録: 検討経緯

| 案 | 内容 | 判断 |
|---|---|---|
| A: PAYG 昇格 | 4 OCPU/24GB 維持、容量優先、回収回避。クレカ登録要 | 不採用（完全 $0 を優先） |
| B: 純無料 | 2 OCPU/12GB、容量ガチャと回収リスクを keep-alive + ランブックで受容 | **採用** |
| C: Terraform フル IaC | 再現性最強だが単一インスタンスには過剰、tfstate の私密管理が必要 | 不採用（YAGNI） |

スペック 2 OCPU/12GB は用途（tmux + Claude Code、CPU 負荷は API 待ちが主）に対して十分。
