#!/bin/zsh
#!/bin/bash

# Exit on error
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Setting up VSCode...${NC}"

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
source "${SCRIPT_DIR}/../util.zsh"

# Define dotfiles directory
DOTFILES_DIR="$(util::repo_dir)"
VSCODE_DIR="${DOTFILES_DIR}/vscode"

# Check if directory exists
if [[ ! -d "${VSCODE_DIR}" ]]; then
    util::error "VSCode directory not found: ${VSCODE_DIR}"
    exit 1
fi

# Install VSCode if not installed
if ! util::has code; then
    util::info "Installing VSCode..."
    brew install --cask visual-studio-code
fi

# Create VSCode configuration directory
util::info "Creating VSCode configuration directory..."
util::mkdir "${HOME}/Library/Application Support/Code/User"

# Read extensions from vscode/extensions.zsh
util::info "Reading extensions from extensions.zsh..."
if [[ -f "${VSCODE_DIR}/extensions.zsh" ]]; then
    extensions=()
    while IFS= read -r line; do
        # Skip empty lines and comments
        if [[ -n "$line" && ! "$line" =~ ^# ]]; then
            extensions+=("$line")
        fi
    done < "${VSCODE_DIR}/extensions.zsh"
    
    # Install extensions
    util::info "Installing VSCode extensions..."
    for extension in "${extensions[@]}"; do
        util::info "Installing extension: ${extension}..."
        code --install-extension "${extension}" || true
    done
else
    util::warning "extensions.zsh not found at: ${VSCODE_DIR}/extensions.zsh"
fi

# Process settings and keybindings
util::info "Processing VSCode configuration files..."

# Process settings.json
if [[ -f "${VSCODE_DIR}/settings.json_with_comments.rb" ]]; then
    util::info "Processing settings.json from settings.json_with_comments.rb..."
    cp "${VSCODE_DIR}/settings.json_with_comments.rb" "${VSCODE_DIR}/settings.json"
    sed -i '' 's/\/\/.*//' "${VSCODE_DIR}/settings.json" # Remove comment lines
elif [[ ! -f "${VSCODE_DIR}/settings.json" ]]; then
    util::warning "settings.json not found at: ${VSCODE_DIR}/settings.json"
fi

# Process keybindings.json
if [[ -f "${VSCODE_DIR}/keybindings.json_with_comment.rb" ]]; then
    util::info "Processing keybindings.json from keybindings.json_with_comment.rb..."
    cp "${VSCODE_DIR}/keybindings.json_with_comment.rb" "${VSCODE_DIR}/keybindings.json"
    sed -i '' 's/\/\/.*//' "${VSCODE_DIR}/keybindings.json" # Remove comment lines
elif [[ ! -f "${VSCODE_DIR}/keybindings.json" ]]; then
    util::warning "keybindings.json not found at: ${VSCODE_DIR}/keybindings.json"
fi

# Create symlinks
util::info "Creating VSCode configuration symlinks..."
if [[ -f "${VSCODE_DIR}/settings.json" ]]; then
    util::symlink "${VSCODE_DIR}/settings.json" "${HOME}/Library/Application Support/Code/User/settings.json"
fi

if [[ -f "${VSCODE_DIR}/keybindings.json" ]]; then
    util::symlink "${VSCODE_DIR}/keybindings.json" "${HOME}/Library/Application Support/Code/User/keybindings.json"
fi

util::info "VSCode setup completed successfully!" 