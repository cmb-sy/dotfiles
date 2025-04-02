#!/bin/zsh

SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
source "${SCRIPT_DIR}/../util.zsh"

util::info "${YELLOW}brewのセットアップを開始します...${NC}"

export HOMEBREW_NO_AUTO_UPDATE=1

formulas=(
    fzf
    ripgrep
    fd
    bat
    exa
    jq
    yq
    tldr
    git
    zsh
    tmux
    zoxide
    neovim
    nodebrew
    yarn
    sheldon
    Powerlevel10k 
)

brew upgrade

for formula in "${formulas[@]}"; do
    brew install "${formula}"
done

util::info "${GREEN}Homebrewのセットアップが完了しました！${NC}" 