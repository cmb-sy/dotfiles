#!/bin/zsh

source "${HOME}/dotfiles/setup/util.zsh"

MACOS_DIR="$(util::repo_dir)/macos"

util::info "Applying macOS settings..."

# LaunchAgents (iplist symbolic link)
[[ -f "${MACOS_DIR}/system.enviroment.plist" ]] && {
  util::mkdir "${HOME}/Library/LaunchAgents"
  util::symlink "${MACOS_DIR}/system.enviroment.plist" "${HOME}/Library/LaunchAgents/system.enviroment.plist"
}

# macOS defaults
source "${MACOS_DIR}/macos.sh"

util::info "macOS settings completed!"
