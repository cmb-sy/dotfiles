#!/bin/zsh

SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
source "${SCRIPT_DIR}/../util.zsh"

util::info "${YELLOW}Zshのセットアップを開始します...${NC}"

# dotfilesディレクトリの定義
DOTFILES_DIR="$(util::repo_dir)"
ZSH_DIR="${DOTFILES_DIR}/zsh"

# Oh My Zshのインストール確認
if [[ ! -d "${HOME}/.oh-my-zsh" ]]; then
    util::info "Oh My Zshをインストールしています..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# Sheldonのインストール確認
if ! util::has sheldon; then
    util::info "Sheldonをインストールしています..."
    brew install sheldon
fi

# Sheldonの初期化
if [[ ! -d "${HOME}/.config/sheldon" ]]; then
    util::info "Sheldonを初期化しています..."
    if util::is_ci; then
        mkdir -p "${HOME}/.config/sheldon"
        echo '# Sheldon configuration' > "${HOME}/.config/sheldon/plugins.toml"
    else
        sheldon init --shell zsh
    fi
fi

util::info "Zsh設定ファイルのシンボリックリンクを作成しています..."
util::symlink "${ZSH_DIR}/.zshrc" "${HOME}/.zshrc"
util::symlink "${ZSH_DIR}/.zshenv" "${HOME}/.zshenv"
util::symlink "${ZSH_DIR}/.aliases.sh" "${HOME}/.aliases.sh"
util::symlink "${ZSH_DIR}/.function.zsh" "${HOME}/.function.zsh"

util::info "Zshプラグインをインストールしています..."
sheldon add --github zsh-users/zsh-autosuggestions zsh-autosuggestions
sheldon add --github zsh-users/zsh-completions zsh-completions
sheldon add --github zsh-users/zsh-syntax-highlighting zsh-syntax-highlighting

# Zshをデフォルトシェルに設定
if [[ "$SHELL" != "$(which zsh)" ]]; then
    util::info "Zshをデフォルトシェルに設定しています..."
    if util::is_ci; then
        util::info "CI環境ではchshをスキップします"
    else
        chsh -s "$(which zsh)"
    fi
fi

util::info "${GREEN}Zshのセットアップが完了しました！${NC}" 