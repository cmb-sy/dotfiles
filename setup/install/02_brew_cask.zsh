#!/bin/zsh

SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
source "${SCRIPT_DIR}/../util.zsh"

util::info "${YELLOW}brew caskのセットアップを開始します...${NC}"

casks=(
    google-chrome
    visual-studio-code
    cursor
    docker
    slack
    zoom
    notion
)

brew upgrade

for cask in "${casks[@]}"; do
    brew install --cask "${cask}" || true
done

util::info "${GREEN}Homebrewのセットアップが完了しました！${NC}" 