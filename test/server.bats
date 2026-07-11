#!/usr/bin/env bats
# server/ 資材の静的検証。Linux 実機なしで通ることが前提。

REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

@test "packages.txt が存在し、コメント以外の行が5行以上ある" {
  run bash -c "grep -cv -e '^#' -e '^$' '$REPO_DIR/server/packages.txt'"
  [ "$status" -eq 0 ]
  [ "$output" -ge 5 ]
}

@test "cloud-init.yaml が valid YAML である" {
  run python3 -c "import yaml,sys; yaml.safe_load(open('$REPO_DIR/server/cloud-init.yaml'))"
  [ "$status" -eq 0 ]
}

@test "cloud-init.yaml は #cloud-config で始まる" {
  run head -1 "$REPO_DIR/server/cloud-init.yaml"
  [ "$output" = "#cloud-config" ]
}

@test "cloud-init.yaml に Tailscale auth key の placeholder がある（実キーではなく）" {
  run grep -c '{{TAILSCALE_AUTH_KEY}}' "$REPO_DIR/server/cloud-init.yaml"
  [ "$status" -eq 0 ]
}

@test "server/ 配下に秘密情報・実識別子が含まれない" {
  # tskey- (Tailscale), sk-ant- (Anthropic), ocid1. (OCI), ghp_/gho_ (GitHub)
  # exit 1 (no match) のみ pass。exit 2 (grep エラー) を成功扱いしない。
  run grep -rEn 'tskey-[a-zA-Z0-9]|sk-ant-[a-zA-Z0-9]|ocid1\.[a-z]|ghp_[a-zA-Z0-9]|gho_[a-zA-Z0-9]' "$REPO_DIR/server/"
  [ "$status" -eq 1 ]
}

@test "server/ 配下にグローバル IP らしき文字列が含まれない" {
  # IP 文字列のみを抽出してから、行頭アンカー付きの許容フィルタで除外する。
  # unanchored フィルタだと 210.148.55.7 が「10\.」に、5.127.0.1 が「127\.」に
  # 部分一致して素通りする false negative があった。
  # 許容: 0.0.0.0 / 127.x / 10.x / 192.168.x / 100.64-127.x (CGNAT=Tailscale)
  # exit 1 (全て許容レンジ) のみ pass。exit 2 (grep エラー) を成功扱いしない。
  run bash -c "set -o pipefail; grep -rEoh '([0-9]{1,3}\.){3}[0-9]{1,3}' '$REPO_DIR/server/' | grep -vE '^(0\.0\.0\.0|127\.|10\.|192\.168\.|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.)'"
  [ "$status" -eq 1 ]
}

@test "server/install.zsh が zsh 構文として正しい" {
  run zsh -n "$REPO_DIR/server/install.zsh"
  [ "$status" -eq 0 ]
}

@test "setup/install.zsh が zsh 構文として正しい（Linux分岐追加後）" {
  run zsh -n "$REPO_DIR/setup/install.zsh"
  [ "$status" -eq 0 ]
}

@test "setup/install.zsh は Linux では server/install.zsh へ委譲する" {
  # 文字列の単純な言及ではなく、Linux 判定分岐の直後に exec 委譲があることを検証する。
  # 行頭アンカーによりコメントアウトされた exec 行は match しない。
  run bash -c "grep -A4 'uname -s.*Linux' '$REPO_DIR/setup/install.zsh' | grep -Ec '^[[:space:]]*exec zsh.*server/install\.zsh'"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "tmux.service は boot 常設の user unit である" {
  run grep -c 'WantedBy=default.target' "$REPO_DIR/server/tmux.service"
  [ "$status" -eq 0 ]
}

@test "keepalive.timer は日次実行の設定を持つ" {
  run grep -c 'OnCalendar=' "$REPO_DIR/server/keepalive.timer"
  [ "$status" -eq 0 ]
}

@test "keepalive.service は CPU 負荷を2時間発生させる" {
  run grep -c -- '--cpu-load 60 --timeout 7200' "$REPO_DIR/server/keepalive.service"
  [ "$status" -eq 0 ]
}

@test "bootstrap.zsh が zsh 構文として正しい" {
  run zsh -n "$REPO_DIR/server/bootstrap.zsh"
  [ "$status" -eq 0 ]
}

@test "bootstrap.zsh --dry-run は副作用なしで全ステップを列挙する" {
  # 注意: bash 3.2 (macOS 同梱) の bats では、body 中間の [[ ]] の失敗が ERR trap に
  # 乗らず素通りする（最終行のみ return status 経由で enforce される）。
  # 検出が保証される grep パイプライン形式で assert する。
  run zsh "$REPO_DIR/server/bootstrap.zsh" --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "PLAN: apt packages"
  echo "$output" | grep -qF "PLAN: zsh env (PATH)"
  echo "$output" | grep -qF "PLAN: claude install + login"
  echo "$output" | grep -qF "PLAN: gh auth login"
  echo "$output" | grep -qF "PLAN: systemd user units (tmux, keepalive)"
  echo "$output" | grep -qF "PLAN: claude global CLAUDE.md link"
}

@test "bootstrap.zsh は未知引数を reject して live run に落ちない" {
  # typo（--dry_run 等）が silent に live run へ落ちると実サーバーで副作用が出るため exit 1 必須
  run zsh "$REPO_DIR/server/bootstrap.zsh" --dry_run
  [ "$status" -eq 1 ]
  echo "$output" | grep -qF "Unknown argument"
}
