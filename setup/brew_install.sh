#!/bin/bash

# エラー時に終了
set -e

# ユーティリティ関数の読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/util.zsh"

# インストール中の自動更新を無効化
export HOMEBREW_NO_AUTO_UPDATE=1

echo -e "${YELLOW}Homebrewパッケージのセットアップを開始します...${NC}"

# コマンドラインツール
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

# GUIアプリケーション
casks=(
    docker
    github
    google-chrome
    microsoft-teams
    slack
    sourcetree
    visual-studio-code
    zoom
    claude
    cursor
    notion
    figma
    1password
)

# Homebrewがインストールされていない場合はインストール
if ! command -v brew &> /dev/null; then
    echo -e "${YELLOW}Homebrewをインストールしています...${NC}"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# brew doctorを実行
echo -e "${YELLOW}brew doctorを実行しています...${NC}"
brew doctor

echo -e "${YELLOW}brew updateを実行しています...${NC}"
brew update

echo -e "${YELLOW}brew upgradeを実行しています...${NC}"
brew upgrade

# 必要なtapを追加
echo -e "${YELLOW}必要なtapを追加しています...${NC}"
# brew tap homebrew/cask-fonts  # 非推奨のtap、削除されました
brew tap ktr0731/evans
brew tap jesseduffield/lazydocker

# コマンドラインツールのインストール
echo -e "${YELLOW}コマンドラインツールをインストールしています...${NC}"
for formula in "${formulas[@]}"; do
    echo -e "${YELLOW}${formula}をインストールしています...${NC}"
    brew install "$formula"
done

# GUIアプリケーションのインストール
echo -e "${YELLOW}GUIアプリケーションをインストールしています...${NC}"
for cask in "${casks[@]}"; do
    echo -e "${YELLOW}${cask}をインストールしています...${NC}"
    brew install --cask "$cask"
done

# macOSでGCCシンボリックリンクのセットアップ
if [[ "$(uname)" == "Darwin" ]]; then
    echo -e "${YELLOW}GCCシンボリックリンクをセットアップしています...${NC}"
    GCC_VER=$(ls $(brew --prefix)/bin | grep -E "^g\+\+\-(\d+) \->" | awk '{print $1}' | sed -e "s/g++-//g")
    sudo ln -snfv "$(brew --prefix gcc)/gcc-${GCC_VER}" /usr/local/bin/gcc
    sudo ln -snfv "$(brew --prefix gcc)/g++-${GCC_VER}" /usr/local/bin/g++
fi

# starshipがインストールされている場合は初期化
if command -v starship &> /dev/null; then
    echo -e "${YELLOW}starshipを初期化しています...${NC}"
    eval "$(starship init bash)"
fi

# クリーンアップ
unset HOMEBREW_NO_AUTO_UPDATE

echo -e "${GREEN}Homebrewパッケージのインストールが正常に完了しました！${NC}"
