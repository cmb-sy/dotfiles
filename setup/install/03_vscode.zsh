#!/bin/zsh

SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
source "${SCRIPT_DIR}/../util.zsh"

util::info "${YELLOW}Starting VSCode setup...${NC}"

# Define dotfiles directory
DOTFILES_DIR="$(util::repo_dir)"
VSCODE_DIR="${DOTFILES_DIR}/vscode"

#----------------------------------------------------------
# Install extensions
#----------------------------------------------------------
util::info "Loading VSCode extensions list from extensions.zsh..."
if [[ -f "${VSCODE_DIR}/extensions.zsh" ]]; then
    # Load extensions - skip comment lines and empty lines
    extensions=()
    while IFS= read -r line; do
        # Skip empty lines and comment lines
        if [[ -n "$line" && ! "$line" =~ ^# ]]; then
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

util::info "${GREEN}VSCode setup completed!${NC}" 