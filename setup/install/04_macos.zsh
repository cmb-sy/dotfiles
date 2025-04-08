#!/bin/zsh

source "${HOME}/dotfiles/setup/util.zsh"

MACOS_DIR="$(util::repo_dir)/macos"

util::info "Starting macOS configuration setup..."


# Create necessary directories
util::mkdir "${HOME}/Library/LaunchAgents"

# Create symbolic links for macOS configuration
util::info "Creating symbolic links for macOS configuration..."
if [[ -f "${MACOS_DIR}/system.enviroment.plist" ]]; then
    util::symlink "${MACOS_DIR}/system.enviroment.plist" "${HOME}/Library/LaunchAgents/system.enviroment.plist"
fi

# Apply macOS configuration
util::info "Applying macOS configuration..."
if [[ -f "${MACOS_DIR}/macos.sh" ]]; then
    source "${MACOS_DIR}/macos.sh"
else
    util::warning "macOS configuration file not found: ${MACOS_DIR}/macos.sh"
fi

util::info "macOS configuration setup completed!" 