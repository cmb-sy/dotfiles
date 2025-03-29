#!/bin/zsh
# macOS設定のセットアップ

# ユーティリティ関数の読み込み
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
source "${SCRIPT_DIR}/../util.zsh"

# dotfilesディレクトリの定義
DOTFILES_DIR="$(util::repo_dir)"
MACOS_DIR="${DOTFILES_DIR}/macos"

util::info "macOS設定のセットアップを開始します..."

# ディレクトリの存在確認
if [[ ! -d "${MACOS_DIR}" ]]; then
    util::error "macOSディレクトリが見つかりません: ${MACOS_DIR}"
    exit 1
fi

# macOS上で実行されているか確認
if ! util::is_mac; then
    util::error "このスクリプトはmacOS専用です"
    exit 1
fi

# 必要なディレクトリを作成
util::mkdir "${HOME}/Library/LaunchAgents"

# macOS設定のシンボリックリンク作成
util::info "macOS設定のシンボリックリンクを作成しています..."
if [[ -f "${MACOS_DIR}/system.enviroment.plist" ]]; then
    util::symlink "${MACOS_DIR}/system.enviroment.plist" "${HOME}/Library/LaunchAgents/system.enviroment.plist"
fi

# macOS設定の適用
util::info "macOS設定を適用しています..."
if [[ -f "${MACOS_DIR}/macos.sh" ]]; then
    source "${MACOS_DIR}/macos.sh"
else
    util::warning "macOS設定ファイルが見つかりません: ${MACOS_DIR}/macos.sh"
fi

util::info "macOS設定のセットアップが完了しました！" 