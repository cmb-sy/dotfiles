#!/bin/zsh

source "${HOME}/dotfiles/setup/util.zsh"

util::info "Starting brew setup..."

export HOMEBREW_NO_AUTO_UPDATE=1

formulas=(
    fzf
    git
    zsh
    yarn
    sheldon
    starship
    uv
    tmux
)

brew upgrade

for formula in "${formulas[@]}"; do
    brew install "${formula}"
done

util::info "${GREEN}Homebrew setup completed!${NC}" 
