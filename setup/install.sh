#!/bin/bash

set -e

# ユーティリティ関数の読み込み
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/util.zsh"

util::info "dotfilesのインストールを開始します..."

# macOS上で実行されているか確認
if ! util::is_mac; then
    util::error "このスクリプトはmacOS専用です"
    exit 1
fi

# ディレクトリを作成
util::info "ディレクトリを作成しています..."
util::mkdir "${HOME}/.config"
util::mkdir "${HOME}/.config/cursor/rules"
util::mkdir "${HOME}/Library/Application Support/Code/User"
util::mkdir "${HOME}/Library/LaunchAgents"

# dotfilesディレクトリの定義
DOTFILES_DIR="$(util::repo_dir)"

# すべてのインストールスクリプトを実行または確認を要求
if [[ ${FORCE} = 1 ]] || util::is_ci; then
    util::info "強制モードですべてのインストールスクリプトを実行しています..."
    for script in "${SCRIPT_DIR}/install"/*.zsh; do
        script_name="$(basename "${script}")"
        util::info "${script_name}を実行しています..."
        zsh "${script}"
    done
else
    # 各インストールスクリプトについて確認
    for script in "${SCRIPT_DIR}/install"/*.zsh; do
        script_name="$(basename "${script}")"
        util::confirm "${script_name}を実行しますか？"
        if [[ $? = 0 ]]; then
            util::info "${script_name}を実行しています..."
            zsh "${script}"
        else
            util::warning "${script_name}をスキップしています..."
        fi
    done
fi

util::info "インストールが正常に完了しました！"
util::info "変更を適用するためにターミナルを再起動してください。"

