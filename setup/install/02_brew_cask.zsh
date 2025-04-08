#!/bin/zsh

source "${HOME}/dotfiles/setup/util.zsh"

util::info "Starting brew cask setup..."

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