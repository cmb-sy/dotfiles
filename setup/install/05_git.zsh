#!/bin/zsh

SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
source "${SCRIPT_DIR}/../util.zsh"

# ディレクトリの設定
DOTFILES_DIR="$(util::repo_dir)"
GIT_DIR="${DOTFILES_DIR}/git"

util::info "${YELLOW}Gitのセットアップを開始します...${NC}"

# ディレクトリの存在確認
if [[ ! -d "${GIT_DIR}" ]]; then
    util::error "Gitディレクトリが見つかりません: ${GIT_DIR}"
    exit 1
fi

# Gitがインストールされていない場合はインストール
if ! util::has git; then
    util::info "Gitをインストールしています..."
    brew install git
fi

# Git設定のシンボリックリンク作成
util::info "Git設定のシンボリックリンクを作成しています..."
util::symlink "${GIT_DIR}/.gitconfig" "${HOME}/.gitconfig"

# グローバルgitignoreのシンボリックリンク作成
util::info "グローバルgitignoreのシンボリックリンクを作成しています..."
util::symlink "${DOTFILES_DIR}/.gitignore_global" "${HOME}/.gitignore_global"

# Gitユーザーが設定されていない場合は設定
if ! git config --global user.name &>/dev/null; then
    if ! util::is_ci; then
        util::info "Gitユーザーを設定しています..."
        read "?Gitユーザー名を入力してください: " username
        read "?Gitメールアドレスを入力してください: " email
        git config --global user.name "$username"
        git config --global user.email "$email"
    else
        util::info "CI環境で実行中、デフォルトのGitユーザーを設定しています..."
        git config --global user.name "CI User"
        git config --global user.email "ci-user@example.com"
    fi
fi

# Gitのデフォルト設定
util::info "Gitのデフォルト設定を構成しています..."
git config --global init.defaultBranch main
git config --global pull.rebase false
git config --global core.editor "vim"
git config --global core.excludesfile ~/.gitignore_global
git config --global github.user cmb-sy

util::info "${GREEN}Gitのセットアップが完了しました！${NC}" 