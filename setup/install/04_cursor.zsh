#!/bin/zsh

SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
source "${SCRIPT_DIR}/../util.zsh"

# Define dotfiles directory
DOTFILES_DIR="$(util::repo_dir)"
CONFIG_DIR="${DOTFILES_DIR}/.config"

util::info "${YELLOW}Starting Cursor setup...${NC}"

# Check if configuration directory exists
if [[ ! -d "${CONFIG_DIR}" ]]; then
    util::info "Creating configuration directory: ${CONFIG_DIR}"
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

# Create symbolic links for Cursor configuration
util::info "Creating symbolic links for Cursor configuration..."

# Create assistant.mdc if it doesn't exist
if [[ ! -f "${CURSOR_RULES_DIR}/assistant.mdc" ]]; then
    util::info "Creating default assistant.mdc file..."
    
    # Create default configuration
    cat > "${CURSOR_RULES_DIR}/assistant.mdc" << 'EOL'
# Cursor AI Assistant Configuration

## General Settings
- Language: English
- Code Style: Clean and Modern
- Documentation: Comprehensive explanation with comments

## Code Generation Rules
1. Always include necessary imports
2. Follow language-specific style guides
3. Use meaningful variable names
4. Include appropriate type hints
5. Include docstrings for functions and classes
EOL
fi

# Create symbolic link for assistant.mdc
util::symlink "${CURSOR_RULES_DIR}/assistant.mdc" "${HOME}/.config/cursor/rules/assistant.mdc"

util::info "${GREEN}Cursor setup completed!${NC}" 