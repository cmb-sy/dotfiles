#!/bin/zsh

source "${HOME}/dotfiles/setup/util.zsh"

MACOS_DIR="$(util::repo_dir)/macos"

util::info "Applying macOS settings..."

# macOS defaults
source "${MACOS_DIR}/macos.sh"

util::info "macOS settings completed!"
