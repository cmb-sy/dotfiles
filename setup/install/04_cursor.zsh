#!/bin/zsh

SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
source "${SCRIPT_DIR}/../util.zsh"

# dotfilesディレクトリの定義
DOTFILES_DIR="$(util::repo_dir)"
CONFIG_DIR="${DOTFILES_DIR}/.config"

util::info "${YELLOW}Cursorのセットアップを開始します...${NC}"

# 設定ディレクトリの存在確認
if [[ ! -d "${CONFIG_DIR}" ]]; then
    util::info "設定ディレクトリを作成します: ${CONFIG_DIR}"
    util::mkdir "${CONFIG_DIR}"
    util::mkdir "${CONFIG_DIR}/cursor/rules"
fi

# Cursorがインストールされていない場合はインストール
if ! mdfind "kMDItemCFBundleIdentifier == 'com.cursor.Cursor'" &>/dev/null; then
    util::info "Cursorをインストールしています..."
    brew install --cask cursor
fi

# Cursor設定ディレクトリの作成
util::info "Cursor設定ディレクトリを作成しています..."
util::mkdir "${HOME}/.config/cursor/rules"

# assistant.mdcが存在しない場合は作成または更新
CURSOR_RULES_DIR="${CONFIG_DIR}/cursor/rules"
if [[ ! -d "${CURSOR_RULES_DIR}" ]]; then
    util::mkdir "${CURSOR_RULES_DIR}"
fi

# Cursor設定のシンボリックリンク作成
util::info "Cursor設定のシンボリックリンクを作成しています..."

# assistant.mdcが存在しない場合は作成
if [[ ! -f "${CURSOR_RULES_DIR}/assistant.mdc" ]]; then
    util::info "デフォルトのassistant.mdcファイルを作成しています..."
    
    # デフォルト設定を作成
    cat > "${CURSOR_RULES_DIR}/assistant.mdc" << 'EOL'
# Cursor AI アシスタント設定

## 一般設定
- 言語: 日本語
- コードスタイル: クリーンでモダン
- ドキュメント: 日本語コメント付きの包括的な説明

## コード生成ルール
1. 必要なインポートを常に含める
2. 言語固有のスタイルガイドに従う
3. 意味のある変数名を使用する
4. 適切な型ヒントを含める
5. 関数とクラスにドキュメント文字列を含める
EOL
fi

# assistant.mdcのシンボリックリンク作成
util::symlink "${CURSOR_RULES_DIR}/assistant.mdc" "${HOME}/.config/cursor/rules/assistant.mdc"

util::info "${GREEN}Cursorのセットアップが完了しました！${NC}" 