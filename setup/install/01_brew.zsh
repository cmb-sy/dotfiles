#!/bin/zsh

SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
source "${SCRIPT_DIR}/../util.zsh"

util::info "brewのセットアップを開始します..."

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
    sheldon
    tmux
    zoxide
    
    neovim
    nodebrew
    yarn
)

brew upgrade

for formula in "${formulas[@]}"; do
    brew install "${formula}"
done

util::info "Homebrewのセットアップが完了しました！" 