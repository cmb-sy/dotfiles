#!/bin/zsh

# ユーティリティ関数の読み込み
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
source "${SCRIPT_DIR}/../util.zsh"

util::info "Homebrewのセットアップを開始します..."

# インストール中の自動更新を無効化
export HOMEBREW_NO_AUTO_UPDATE=1

# インストールするコマンドラインツール
formulas=(
    # シェルユーティリティ
    fzf
    ripgrep
    fd
    bat
    exa
    jq
    yq
    tldr
    
    # バージョン管理
    git
    gh
    hub
    git-delta
    
    # シェル拡張
    zsh
    starship
    sheldon
    tmux
    zoxide
    
    # 開発ツール
    neovim
    nodebrew
    yarn
)

# インストールするGUIアプリケーション
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

# Homebrewがインストールされていない場合はインストール
if ! util::has brew; then
    util::info "Homebrewをインストールしています..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # HomebrewをPATHに追加
    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
fi

# brew doctorと更新を実行
util::info "brew doctorを実行しています..."
brew doctor

util::info "brew updateを実行しています..."
brew update

# 必要なtapを追加
util::info "必要なtapを追加しています..."
# brew tap homebrew/cask-fonts  # 非推奨のtap、削除されました
brew tap ktr0731/evans
brew tap jesseduffield/lazydocker

# コマンドラインツールのインストール
util::info "コマンドラインツールをインストールしています..."
for formula in "${formulas[@]}"; do
    util::info "${formula}をインストールしています..."
    brew install "${formula}" || true
done

# GUIアプリケーションのインストール
util::info "GUIアプリケーションをインストールしています..."
for cask in "${casks[@]}"; do
    util::info "${cask}をインストールしています..."
    brew install --cask "${cask}" || true
done

# クリーンアップ
unset HOMEBREW_NO_AUTO_UPDATE

util::info "Homebrewのセットアップが完了しました！" 