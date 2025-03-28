#!/bin/zsh
# Homebrew installation and package setup

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
source "${SCRIPT_DIR}/../util.zsh"

util::info "Setting up Homebrew..."

# Disable auto-update during installation
export HOMEBREW_NO_AUTO_UPDATE=1

# Command line tools to install
formulas=(
    # Shell utilities
    fzf
    ripgrep
    fd
    bat
    exa
    jq
    yq
    tldr
    
    # Version control
    git
    gh
    hub
    git-delta
    
    # Shell enhancements
    zsh
    starship
    sheldon
    tmux
    zoxide
    
    # Development tools
    neovim
    nodebrew
    yarn
)

# GUI applications to install
casks=(
    # Browsers
    google-chrome
    
    # Development tools
    visual-studio-code
    cursor
    iterm2
    docker
    postman
    
    # Communication
    slack
    zoom
    
    # Productivity
    notion
    rectangle
    alfred
)

# Install Homebrew if not installed
if ! util::has brew; then
    util::info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # Add Homebrew to PATH
    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
fi

# Run brew doctor and update
util::info "Running brew doctor..."
brew doctor

util::info "Running brew update..."
brew update

# Add required taps
util::info "Adding required taps..."
# brew tap homebrew/cask-fonts  # Deprecated tap, removed
brew tap ktr0731/evans
brew tap jesseduffield/lazydocker

# Install formulas
util::info "Installing command line tools..."
for formula in "${formulas[@]}"; do
    util::info "Installing ${formula}..."
    brew install "${formula}" || true
done

# Install casks
util::info "Installing GUI applications..."
for cask in "${casks[@]}"; do
    util::info "Installing ${cask}..."
    brew install --cask "${cask}" || true
done

# Clean up
unset HOMEBREW_NO_AUTO_UPDATE

util::info "Homebrew setup completed successfully!" 