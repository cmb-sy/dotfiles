#!/bin/zsh

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
source "${SCRIPT_DIR}/../util.zsh"

# Define dotfiles directory
DOTFILES_DIR="$(util::repo_dir)"
CONFIG_DIR="${DOTFILES_DIR}/.config"

util::info "Setting up Cursor..."

# Check if config directory exists
if [[ ! -d "${CONFIG_DIR}" ]]; then
    util::info "Creating config directory: ${CONFIG_DIR}"
    util::mkdir "${CONFIG_DIR}"
    util::mkdir "${CONFIG_DIR}/cursor/rules"
fi

# Install Cursor if not installed
if ! mdfind "kMDItemCFBundleIdentifier == 'com.cursor.Cursor'" &>/dev/null; then
    util::info "Installing Cursor..."
    brew install --cask cursor
fi

# Create Cursor configuration directory
util::info "Creating Cursor configuration directory..."
util::mkdir "${HOME}/.config/cursor/rules"

# Create or update assistant.mdc if it doesn't exist
CURSOR_RULES_DIR="${CONFIG_DIR}/cursor/rules"
if [[ ! -d "${CURSOR_RULES_DIR}" ]]; then
    util::mkdir "${CURSOR_RULES_DIR}"
fi

# Create symlinks for Cursor configuration
util::info "Creating Cursor configuration symlinks..."

# Create assistant.mdc if it doesn't exist
if [[ ! -f "${CURSOR_RULES_DIR}/assistant.mdc" ]]; then
    util::info "Creating default assistant.mdc file..."
    
    # Create default config
    cat > "${CURSOR_RULES_DIR}/assistant.mdc" << 'EOL'
# Cursor AI Assistant Configuration

## General Settings
- Language: Japanese
- Code Style: Clean and Modern
- Documentation: Comprehensive with Japanese comments

## Code Generation Rules
1. Always include necessary imports
2. Follow language-specific style guides
3. Use meaningful variable names
4. Add type hints where appropriate
5. Include docstrings for functions and classes
EOL
fi

# Create symlink for assistant.mdc
util::symlink "${CURSOR_RULES_DIR}/assistant.mdc" "${HOME}/.config/cursor/rules/assistant.mdc"

util::info "Cursor setup completed successfully!" 