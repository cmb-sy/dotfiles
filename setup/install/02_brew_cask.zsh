#!/bin/zsh

SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
source "${SCRIPT_DIR}/../util.zsh"

util::info "${YELLOW}brew caskのセットアップを開始します...${NC}"

# GUIアプリケーション
casks=(
    # ブラウザ
    google-chrome
    
    # 開発ツール
    visual-studio-code
    cursor
    iterm2
    docker
    postman
    
    # コミュニケーション
    slack
    zoom
    
    # その他
    notion
    rectangle
    alfred
)

brew upgrade

for cask in "${casks[@]}"; do
    brew install --cask "${cask}" || true
done

util::info "Homebrewのセットアップが完了しました！" 