#!/bin/zsh
# OCI サーバー（Ubuntu arm64）用の非対話パッケージ導入。冪等。
# 使い方: zsh ~/dotfiles/server/install.zsh
set -e

SCRIPT_DIR="${0:A:h}"
REPO_DIR="${SCRIPT_DIR:h}"
source "${REPO_DIR}/setup/util.zsh"

if [[ "$(uname -s)" != "Linux" ]]; then
  util::warning "server/install.zsh is for Linux servers only. Aborting."
  exit 1
fi

util::info "Installing apt packages from server/packages.txt..."
sudo apt-get update -qq
grep -v -e '^#' -e '^$' "${SCRIPT_DIR}/packages.txt" | xargs sudo apt-get install -y -qq

# デフォルトシェルを zsh に（冪等）
if [[ "$(getent passwd "$USER" | cut -d: -f7)" != "$(command -v zsh)" ]]; then
  sudo chsh -s "$(command -v zsh)" "$USER"
  util::info "Default shell changed to zsh (takes effect next login)."
fi

util::info "Done. Next: zsh ~/dotfiles/server/bootstrap.zsh"
