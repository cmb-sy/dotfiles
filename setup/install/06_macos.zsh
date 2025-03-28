#!/bin/zsh
# macOS configuration setup

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
source "${SCRIPT_DIR}/../util.zsh"

# Define dotfiles directory
DOTFILES_DIR="$(util::repo_dir)"
MACOS_DIR="${DOTFILES_DIR}/macos"

util::info "Setting up macOS configuration..."

# Check if directory exists
if [[ ! -d "${MACOS_DIR}" ]]; then
    util::error "macOS directory not found: ${MACOS_DIR}"
    exit 1
fi

# Check if running on macOS
if ! util::is_mac; then
    util::error "This script is only for macOS"
    exit 1
fi

# Create necessary directories
util::mkdir "${HOME}/Library/LaunchAgents"

# Create symlinks for macOS configuration
util::info "Creating macOS configuration symlinks..."
if [[ -f "${MACOS_DIR}/system.enviroment.plist" ]]; then
    util::symlink "${MACOS_DIR}/system.enviroment.plist" "${HOME}/Library/LaunchAgents/system.enviroment.plist"
fi

# Apply macOS settings
util::info "Applying macOS settings..."
if [[ -f "${MACOS_DIR}/macos.sh" ]]; then
    source "${MACOS_DIR}/macos.sh"
else
    util::warning "macOS settings file not found: ${MACOS_DIR}/macos.sh"
fi

util::info "macOS setup completed successfully!" 