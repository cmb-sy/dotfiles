#!/bin/zsh

SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
source "${SCRIPT_DIR}/../util.zsh"

util::info "${YELLOW}VSCodeのセットアップを開始します...${NC}"

# dotfilesディレクトリの定義
DOTFILES_DIR="$(util::repo_dir)"
VSCODE_DIR="${DOTFILES_DIR}/vscode"

# VSCodeのインストール確認
if ! util::has code; then
    util::info "VSCodeをインストールしています..."
    brew install --cask visual-studio-code
fi

# 拡張機能のインストール
util::info "extensions.zshからVSCode拡張機能リストを読み込んでいます..."
if [[ -f "${VSCODE_DIR}/extensions.zsh" ]]; then
    # 拡張機能の読み込み - コメント行と空行をスキップ
    extensions=()
    while IFS= read -r line; do
        # 空行とコメント行をスキップ
        if [[ -n "$line" && ! "$line" =~ ^# ]]; then
            # コメント部分を削除して拡張機能IDだけを取得
            extension_id=$(echo "$line" | awk '{print $1}')
            extensions+=("$extension_id")
        fi
    done < "${VSCODE_DIR}/extensions.zsh"
    
    util::info "VSCode拡張機能をインストールしています..."
    for extension in "${extensions[@]}"; do
        util::info "拡張機能をインストール中: ${extension}..."
        code --install-extension "${extension}" || true
    done
else
    util::warning "extensions.zshファイルが見つかりません: ${VSCODE_DIR}/extensions.zsh"
fi

# 設定ファイルの処理
util::info "VSCode設定ファイルをセットアップしています..."

# settings.jsonの処理
if [[ -f "${VSCODE_DIR}/settings.json" ]]; then
    util::info "settings.jsonを適用しています..."
    util::symlink "${VSCODE_DIR}/settings.json" "${HOME}/Library/Application Support/Code/User/settings.json"
else
    util::warning "settings.jsonが見つかりません: ${VSCODE_DIR}/settings.json"
fi

# keybindings.jsonの処理
if [[ -f "${VSCODE_DIR}/keybindings.json" ]]; then
    util::info "keybindings.jsonを適用しています..."
    util::symlink "${VSCODE_DIR}/keybindings.json" "${HOME}/Library/Application Support/Code/User/keybindings.json"
else
    util::warning "keybindings.jsonが見つかりません: ${VSCODE_DIR}/keybindings.json"
fi

util::info "${GREEN}VSCodeのセットアップが完了しました！${NC}" 