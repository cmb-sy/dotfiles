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
  run grep -rEn 'tskey-[a-zA-Z0-9]|sk-ant-[a-zA-Z0-9]|ocid1\.[a-z]|ghp_[a-zA-Z0-9]|gho_[a-zA-Z0-9]' "$REPO_DIR/server/"
  [ "$status" -ne 0 ]
}

@test "server/ 配下にグローバル IP らしき文字列が含まれない" {
  # 0.0.0.0 / 127.x / 100.64-127.x (CGNAT=Tailscale) / 10.x / 192.168.x は許容
  run bash -c "grep -rEn '([0-9]{1,3}\.){3}[0-9]{1,3}' '$REPO_DIR/server/' | grep -vE '0\.0\.0\.0|127\.|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.|10\.|192\.168\.'"
  [ "$status" -ne 0 ]
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
