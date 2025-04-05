#!/bin/zsh

SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
source "${SCRIPT_DIR}/../util.zsh"

util::info "${YELLOW}Starting VSCode setup...${NC}"

# Define dotfiles directory
DOTFILES_DIR="$(util::repo_dir)"
VSCODE_DIR="${DOTFILES_DIR}/vscode"

# Check if VSCode is installed
if ! util::has code; then
    util::info "Installing VSCode..."
    brew install --cask visual-studio-code
fi

# Install extensions
util::info "Loading VSCode extensions list from extensions.zsh..."
if [[ -f "${VSCODE_DIR}/extensions.zsh" ]]; then
    # Load extensions - skip comment lines and empty lines
    extensions=()
    while IFS= read -r line; do
        # Skip empty lines and comment lines
        if [[ -n "$line" && ! "$line" =~ ^# ]]; then
            # Get only extension ID by removing comment part
            extension_id=$(echo "$line" | awk '{print $1}')
            extensions+=("$extension_id")
        fi
    done < "${VSCODE_DIR}/extensions.zsh"
    
    util::info "Installing VSCode extensions..."
    for extension in "${extensions[@]}"; do
        util::info "Installing extension: ${extension}..."
        code --install-extension "${extension}" || true
    done
else
    util::warning "extensions.zsh file not found: ${VSCODE_DIR}/extensions.zsh"
fi

# Process configuration files
util::info "Setting up VSCode configuration files..."

# Process settings.json
if [[ -f "${VSCODE_DIR}/settings.json" ]]; then
    util::info "Applying settings.json..."
    util::symlink "${VSCODE_DIR}/settings.json" "${HOME}/Library/Application Support/Code/User/settings.json"
else
    util::warning "settings.json not found: ${VSCODE_DIR}/settings.json"
fi

# Process keybindings.json
if [[ -f "${VSCODE_DIR}/keybindings.json" ]]; then
    util::info "Applying keybindings.json..."
    util::symlink "${VSCODE_DIR}/keybindings.json" "${HOME}/Library/Application Support/Code/User/keybindings.json"
else
    util::warning "keybindings.json not found: ${VSCODE_DIR}/keybindings.json"
fi

util::info "${GREEN}VSCode setup completed!${NC}" 