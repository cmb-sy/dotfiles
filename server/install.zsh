#!/bin/zsh
# Non-interactive package install for the OCI server (Ubuntu arm64). Idempotent.
# Usage: zsh ~/dotfiles/server/install.zsh
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

# Set the default shell to zsh (idempotent)
if [[ "$(getent passwd "$USER" | cut -d: -f7)" != "$(command -v zsh)" ]]; then
  sudo chsh -s "$(command -v zsh)" "$USER"
  util::info "Default shell changed to zsh (takes effect next login)."
fi

util::info "Done. Next: zsh ~/dotfiles/server/bootstrap.zsh"
