#!/bin/zsh

source "${HOME}/dotfiles/setup/util.zsh"

util::info "Starting VSCode setup..."

#----------------------------------------------------------
# Install extensions
#----------------------------------------------------------
util::info "Loading VSCode extensions list from extensions.zsh..."
if [[ -f "${HOME}/dotfiles/vscode/extensions.zsh" ]]; then
    # Load extensions - skip comment lines and empty lines
    extensions=()
    while IFS= read -r line; do
        # Skip empty lines and comment lines
        if [[ -n "$line" && ! "$line" =~ ^# ]]; then
            extension_id=$(echo "$line" | awk '{print $1}')
            extensions+=("$extension_id")
        fi
    done < "${HOME}/dotfiles/vscode/extensions.zsh"
    
    util::info "Installing VSCode extensions..."
    for extension in "${extensions[@]}"; do
        util::info "Installing extension: ${extension}..."
        code --install-extension "${extension}" || true
    done
else
    util::warning "extensions.zsh file not found: ${HOME}/dotfiles/vscode/extensions.zsh"
fi

util::info "VSCode setup completed!" 