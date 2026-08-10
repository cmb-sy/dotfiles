#!/bin/zsh

source "${0:A:h:h}/setup/util.zsh"

MACOS_DIR="${0:A:h}"

util::info "Applying macOS settings..."

# macOS defaults
source "${MACOS_DIR}/macos.sh"

util::info "macOS settings completed!"
