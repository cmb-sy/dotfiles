# OCI 無料枠 Claude 常駐サーバー

Oracle Cloud Infrastructure (OCI) の Always Free 枠で Claude Code を 24 時間常駐させるための
再構築ランブック。設計の背景は
[docs/superpowers/specs/2026-07-11-oci-claude-server-design.md](../docs/superpowers/specs/2026-07-11-oci-claude-server-design.md)
を参照。

**受け入れ条件: この README 単体で、アカウントさえあれば 30 分以内に再構築が完了すること。**

無料枠のインスタンスは idle 回収・アカウント整理でいつ消えてもおかしくない。
だからこのサーバーは「ペット」ではなく「家畜 (cattle)」として扱う:

- サーバー上にしか無い状態を作らない（成果物は常に git push、認証は再発行可能なもののみ）
- 消えたら直すのではなく、この README の手順で作り直す（目標 30 分）
- 手順は全てこのリポジトリにコード化されており、Mac や既存環境が無くても GitHub 上の
  この README だけで再現できる

## 構成

```
[Mac / iPhone]
   │  tailscale ssh（tailnet 内通信のみ。公開ポートなし）
   ▼
[OCI VM.Standard.A1.Flex  2 OCPU / 12GB RAM / Ubuntu 24.04 (aarch64)]
   ├─ tailscaled ...... outbound のみで tailnet に参加（ingress 全閉じで成立）
   ├─ tmux.service .... boot 時から tmux セッション "main" を常設（user unit）
   ├─ keepalive.timer . 毎日 2 時間 stress-ng で CPU 負荷（idle 回収対策）
   └─ Claude Code + gh  /login / gh auth で認証
```

| ファイル | 役割 |
| --- | --- |
| `cloud-init.yaml` | インスタンス作成時に貼るテンプレ。Tailscale 参加と dotfiles clone まで自動化 |
| `install.zsh` | apt パッケージの非対話インストール（`packages.txt` を読む） |
| `bootstrap.zsh` | 初回セットアップ本体。冪等。`--dry-run` で計画のみ表示 |
| `tmux.service` | tmux 常設用 systemd user unit |
| `keepalive.{service,timer}` | idle 回収対策の日次 CPU 負荷 |
| `../test/server.bats` | この README を含む `server/` 全体の静的検証（秘密情報スキャン含む） |

## 前提アカウント（全て無料で維持できる）

1. **OCI アカウント** — §1 で作成
2. **Tailscale アカウント** — <https://login.tailscale.com> 。Mac / iPhone も同じ tailnet に参加させておく
3. **GitHub アカウント** — このリポジトリ（`cmb-sy/dotfiles`）に読み書きできること
4. **Claude サブスクリプション** — `claude` の `/login` で認証できること

## 1. アカウント作成（初回のみ）

1. <https://www.oracle.com/cloud/free/> からサインアップする。
2. **ホームリージョンは `ap-tokyo-1`（Japan East (Tokyo)）を選ぶ。作成後は変更不可。**
   A1 インスタンスはホームリージョンにしか作れないため、ここを間違えるとやり直しになる。
3. サインアップにクレジットカードの本人確認は必要だが、**Pay As You Go への昇格はしない**
   （純無料アカウントのまま運用する）。昇格すると回収ポリシーは緩むが、課金事故のリスクを負う。
4. 2026-06-15 以降の純無料アカウントの Always Free A1 枠は **2 OCPU / 12GB RAM**（旧 4 OCPU / 24GB から縮小）。
   本構成はこの縮小後の枠に合わせてある。

## 2. インスタンス作成

### 2.1 Tailscale auth key を発行する

1. <https://login.tailscale.com/admin/settings/keys> → **Generate auth key**
2. 設定: **Reusable = OFF（単回使用）/ Expiration = 90 日以下 / Pre-approved = ON / Ephemeral = OFF**
3. 発行されたキーは次のステップで一度使ったら破棄する。**リポジトリ内のファイルに書き込まない。**

### 2.2 cloud-init を準備する

[`server/cloud-init.yaml`](cloud-init.yaml) の内容をコピーし、**リポジトリ外**（エディタの無題バッファ等）で
`{{TAILSCALE_AUTH_KEY}}` を 2.1 のキーに置換する。置換済みの内容を保存・コミットしてはならない。

### 2.3 OCI コンソールでインスタンスを作成する

OCI コンソール →「コンピュート」→「インスタンス」→「インスタンスの作成」:

| 項目 | 値 |
| --- | --- |
| 名前 | 任意（例: `<インスタンス名>`。これがそのまま tailnet ホスト名になる） |
| イメージ | **Canonical Ubuntu 24.04**（A1 シェイプを選ぶと aarch64 版が選択される） |
| シェイプ | **VM.Standard.A1.Flex — 2 OCPU / 12GB**（Always Free 枠の全量を 1 台に割り当てる） |
| VCN / サブネット | 新規作成でよい。パブリック・サブネット + 一時パブリック IPv4 割当て可（次項で ingress を全閉じにするため外部から到達不能） |
| SSH キー | **空でよい**。接続は Tailscale SSH で行う（緊急時はシリアルコンソール接続。§5 参照） |
| ブート・ボリューム | カスタム・サイズ **100GB**（無料枠は合計 200GB まで） |
| cloud-init | 「高度なオプション」→「管理」→ cloud-init スクリプト欄に 2.2 で置換した内容を貼り付け |

**「Out of capacity」エラーが出たら**: 無料アカウントの既知事象。時間帯を変えて再試行する
（早朝・深夜が通りやすい）。設定は保存されないため、この表を見ながら入力し直す。

### 2.4 ingress を全閉じにする

作成直後に「ネットワーキング」→「仮想クラウド・ネットワーク」→ 作成された VCN →
「セキュリティ・リスト」→ Default Security List を開き、**イングレス・ルールを全て削除する**
（デフォルトで入っている `0.0.0.0/0` からの TCP 22 許可も削除）。エグレス・ルールは残す。

Tailscale は outbound 接続だけで tailnet に参加するため、inbound を全閉じにしても接続に支障はない。

### 2.5 参加確認

数分待ってから、Mac（同じ tailnet に参加済み）で:

```sh
tailscale status | grep <tailnetホスト名>
```

表示されれば cloud-init 完了。Tailscale 管理画面（Machines）でも新デバイスとして確認できる。

## 3. 初回セットアップ

### 3.1 接続

```sh
tailscale ssh ubuntu@<tailnetホスト名>
```

cloud-init が `~/dotfiles` に clone 済みであることを確認する（無ければ
`git clone https://github.com/cmb-sy/dotfiles.git ~/dotfiles`）。

### 3.2 bootstrap を実行

```sh
zsh ~/dotfiles/server/bootstrap.zsh --dry-run   # 実行計画の確認（副作用なし）
zsh ~/dotfiles/server/bootstrap.zsh             # 本実行
```

bootstrap は冪等（途中で失敗したら原因を直してそのまま再実行してよい）。以下を行う:

1. **apt パッケージ** — `server/install.zsh` 経由で `packages.txt` を一括導入、ログインシェルを zsh 化
2. **zsh env** — `~/.zshenv` に `~/.local/bin` の PATH を追記（claude の native installer の導入先）
3. **Claude Code** — インストール後、claude が起動するので REPL 内で `/login` を実行する。
   ブラウザの無い環境のため、表示された URL を Mac 側のブラウザで開いて認証コードを貼り戻し、
   完了したら `/exit` で抜ける（未認証のまま抜けると bootstrap は exit 1 で止まる）
4. **gh** — `gh auth login` が対話で起動する。`HTTPS` + `Login with a web browser` を選び、
   ワンタイムコードを Mac 側ブラウザで入力する
5. **systemd user units** — `tmux.service` / `keepalive.timer` を有効化し、
   `loginctl enable-linger` で SSH 切断後もユニットが動き続けるようにする
6. **CLAUDE.md** — グローバル CLAUDE.md を `~/.claude/` に symlink

### 3.3 検証

```sh
systemctl --user status tmux.service keepalive.timer
```

両方が `loaded` / `active` であること（timer は `active (waiting)` で正常）。

> 注: symlink された unit の `enable` が古い systemd で失敗する既知事象がある。失敗時は
> symlink を実コピーに替える: `for u in tmux.service keepalive.service keepalive.timer; do cp -f ~/dotfiles/server/$u ~/.config/systemd/user/$u; done && systemctl --user daemon-reload && systemctl --user enable --now tmux.service keepalive.timer`
>
> `Failed to connect to bus` が出る場合: Tailscale SSH は logind セッションを登録しないため
> `XDG_RUNTIME_DIR` が未設定になる。`export XDG_RUNTIME_DIR=/run/user/$(id -u)` してから再試行する。

続けて動作確認:

```sh
tmux attach -t main        # 常設セッションに入れること（抜けるのは C-b d）
claude --version           # Claude Code が起動すること
gh auth status             # GitHub 認証が通っていること
```

ここまで完了した時点で再構築完了。**§2 開始から 30 分以内に収まらなかった場合、
詰まった手順をこの README に追記してから閉じること**（次回の 30 分を守るため）。

## 4. 日常運用

### 接続

```sh
tailscale ssh ubuntu@<tailnetホスト名>
tmux attach -t main
```

tmux セッション "main" は boot 時から常設されており、SSH が切れても中の Claude Code は生き続ける。

### 使用量の監視

Claude Code 内で `/usage` を実行し、サブスクリプションの使用量を確認する。
**導入後 1〜2 週間は特にこまめに確認し**、常駐運用がプランの上限に収まるか見極める。

### keepalive の受け入れ確認（導入 1 週間後・必須）

OCI は純無料アカウントの idle インスタンスを回収する（7 日間の CPU 95 パーセンタイルが
20% 未満などの条件）。`keepalive.timer` が毎日 2 時間 stress-ng で負荷をかけて対抗している。

**導入 1 週間後、OCI コンソール →「コンピュート」→ インスタンス詳細 → メトリックで
CPU 使用率の 95 パーセンタイルが 20% を超えていることを確認する**（設計の受け入れ試験）。
下回っている場合は `keepalive.service` の `--cpu-load` / `--timeout` を引き上げる。

### バックアップ

OCI コンソール → ブート・ボリューム →「バックアップ・ポリシーの割当て」で週次バックアップを設定する。
**無料枠のバックアップ保持は合計 5 世代まで**のため、定義済みポリシー（Silver 等）ではなく
カスタム・ポリシーで「週次・保持 4 世代」程度に抑える。
ただしバックアップは時短手段にすぎず、復旧の正は常に §2 からの再構築（家畜原則）。

## 5. 障害・回収からの復旧

### 判定フロー

```sh
# Mac から
tailscale status               # 対象ホストが offline か
tailscale ping <tailnetホスト名>
```

offline なら OCI コンソールでインスタンスの状態を確認する:

| コンソール上の状態 | 対応 |
| --- | --- |
| 停止済み (STOPPED) | 「開始」で起動。boot 後に tmux / keepalive は自動復帰する（§3.3 の検証を再実行） |
| 実行中なのに繋がらない | シリアルコンソール接続で中を確認（`systemctl status tailscaled` 等）。ただし調査に 30 分以上かけるなら作り直す方が速い |
| 終了済み / 一覧に無い | **回収された。§2 から再実行（目標 30 分）** |

idle 回収の場合は同じ設定で作り直せばよい。アカウントごと BAN・整理された場合は §1 からやり直す
（別メールアドレスが必要になることがある）。

### 復旧を 30 分で終わらせるための平時の規律

- **成果物は常に git push しておくこと。サーバーにしか無い状態を作らない。**
  作業リポジトリの push 漏れは `gh repo list` と各リポジトリの `git status` で棚卸しできる
- 認証（Tailscale auth key / claude login / gh auth）は全て再発行可能。バックアップ対象にしない
- サーバー固有の設定変更はこのリポジトリの `server/` に反映してから適用する（手作業の一回限り変更を禁止）

## 6. セキュリティ規律

- **このディレクトリと README に実 OCID・実 IP・実キーを書かない。** 例示は全て `<placeholder>` 形式。
  `test/server.bats` が `server/` 配下全ファイルを機械検査する
  （Tailscale key / Anthropic key / OCID / GitHub token の各プレフィックスと、グローバル IP らしき文字列）
- **Tailscale auth key は毎回使い捨てを発行する**（単回使用・有効期限 90 日以下・Pre-approved）。
  置換済み cloud-init はコンソールに貼るだけで、ファイルとして保存・コミットしない
- inbound は全閉じを維持する。ポートを開けたくなったら、まず Tailscale 内で済む方法
  （`tailscale serve` 等）を検討する
- コミット前の自己検査:

```sh
bats test/server.bats
```
