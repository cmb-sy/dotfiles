#!/bin/bash

# Exit on error
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Disable auto-update during installation
export HOMEBREW_NO_AUTO_UPDATE=1

echo -e "${YELLOW}Setting up Homebrew packages...${NC}"

# Command line tools to install
formulas=(
    fzf
    sheldon
    git
    ripgrep
    fd
    bat
    exa
    jq
    yq
    tldr
    gh
    hub
    git-delta
    starship
    neovim
    tmux
    zoxide
    nodebrew
    yarn
)

# GUI applications to install
casks=(
    docker
    github
    google-chrome
    microsoft-teams
    slack
    sourcetree
    visual-studio-code
    zoom
    cursor
    notion
    rectangle
    alfred
    iterm2
    postman
    dbeaver-community
    figma
    1password
    dropbox
    spotify
)

# Install Homebrew if not installed
if ! command -v brew &> /dev/null; then
    echo -e "${YELLOW}Installing Homebrew...${NC}"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Run brew doctor and update
echo -e "${YELLOW}Running brew doctor...${NC}"
brew doctor

echo -e "${YELLOW}Running brew update...${NC}"
brew update

echo -e "${YELLOW}Running brew upgrade...${NC}"
brew upgrade

# Add required taps
echo -e "${YELLOW}Adding required taps...${NC}"
brew tap homebrew/cask-fonts
brew tap ktr0731/evans
brew tap jesseduffield/lazydocker

# Install formulas
echo -e "${YELLOW}Installing command line tools...${NC}"
for formula in "${formulas[@]}"; do
    echo -e "${YELLOW}Installing ${formula}...${NC}"
    brew install "$formula"
done

# Install casks
echo -e "${YELLOW}Installing GUI applications...${NC}"
for cask in "${casks[@]}"; do
    echo -e "${YELLOW}Installing ${cask}...${NC}"
    brew install --cask "$cask"
done

# Set up GCC symlinks on macOS
if [[ "$(uname)" == "Darwin" ]]; then
    echo -e "${YELLOW}Setting up GCC symlinks...${NC}"
    GCC_VER=$(ls $(brew --prefix)/bin | grep -E "^g\+\+\-(\d+) \->" | awk '{print $1}' | sed -e "s/g++-//g")
    sudo ln -snfv "$(brew --prefix gcc)/gcc-${GCC_VER}" /usr/local/bin/gcc
    sudo ln -snfv "$(brew --prefix gcc)/g++-${GCC_VER}" /usr/local/bin/g++
fi

# Initialize starship if installed
if command -v starship &> /dev/null; then
    echo -e "${YELLOW}Initializing starship...${NC}"
    eval "$(starship init bash)"
fi

# Clean up
unset HOMEBREW_NO_AUTO_UPDATE

echo -e "${GREEN}Homebrew packages installation completed successfully!${NC}"
