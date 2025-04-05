#!/bin/zsh

SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
source "${SCRIPT_DIR}/../util.zsh"

util::info "${YELLOW}Starting brew cask setup...${NC}"

casks=(
    google-chrome
    visual-studio-code
    cursor
    docker
    slack
    zoom
    notion
    alacritty
)

brew upgrade

for cask in "${casks[@]}"; do
    brew install --cask "${cask}" || true
done

util::info "${GREEN}Homebrew cask setup completed!${NC}" 