#!/bin/zsh
# macOS configuration setup

SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
source "${SCRIPT_DIR}/../util.zsh"

# Define dotfiles directory
DOTFILES_DIR="$(util::repo_dir)"
MACOS_DIR="${DOTFILES_DIR}/macos"

util::info "${YELLOW}Starting macOS configuration setup...${NC}"

# Check if running on macOS
if ! util::is_mac; then
    util::error "This script is for macOS only"
    exit 1
fi

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

util::info "${GREEN}macOS configuration setup completed!${NC}" 