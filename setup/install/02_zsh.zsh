#!/bin/zsh
#!/bin/bash

# Exit on error
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Setting up Zsh...${NC}"

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
source "${SCRIPT_DIR}/../util.zsh"

# Define dotfiles directory
DOTFILES_DIR="$(util::repo_dir)"
ZSH_DIR="${DOTFILES_DIR}/zsh"

# Check if directory exists
if [[ ! -d "${ZSH_DIR}" ]]; then
    util::error "Zsh directory not found: ${ZSH_DIR}"
    exit 1
fi

# Install Zsh if not installed
if ! util::has zsh; then
    util::info "Installing Zsh..."
    brew install zsh
fi

# Install Oh My Zsh if not installed
if [[ ! -d "${HOME}/.oh-my-zsh" ]]; then
    util::info "Installing Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# Install Sheldon if not installed
if ! util::has sheldon; then
    util::info "Installing Sheldon..."
    brew install sheldon
fi

# Initialize Sheldon
if [[ ! -d "${HOME}/.config/sheldon" ]]; then
    util::info "Initializing Sheldon..."
    if util::is_ci; then
        mkdir -p "${HOME}/.config/sheldon"
        echo '# Sheldon configuration' > "${HOME}/.config/sheldon/plugins.toml"
    else
        sheldon init --shell zsh
    fi
fi

# Install Starship if not installed
if ! util::has starship; then
    util::info "Installing Starship..."
    brew install starship
fi

# Create symlinks for Zsh configuration files
util::info "Creating symlinks for Zsh configuration files..."
util::symlink "${ZSH_DIR}/.zshrc" "${HOME}/.zshrc"
util::symlink "${ZSH_DIR}/.zshenv" "${HOME}/.zshenv"
util::symlink "${ZSH_DIR}/.aliases.sh" "${HOME}/.aliases.sh"
util::symlink "${ZSH_DIR}/.function.zsh" "${HOME}/.function.zsh"

# Install Zsh plugins via Sheldon
util::info "Installing Zsh plugins..."
sheldon add --github zsh-users/zsh-autosuggestions zsh-autosuggestions
sheldon add --github zsh-users/zsh-completions zsh-completions
sheldon add --github zsh-users/zsh-syntax-highlighting zsh-syntax-highlighting

# Set Zsh as default shell
if [[ "$SHELL" != "$(which zsh)" ]]; then
    util::info "Setting Zsh as default shell..."
    if util::is_ci; then
        util::info "Skipping chsh in CI environment"
    else
        chsh -s "$(which zsh)"
    fi
fi

util::info "Zsh setup completed successfully!" 