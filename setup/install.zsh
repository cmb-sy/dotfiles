#!/bin/zsh

# util.zshを読み込む
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
source "${SCRIPT_DIR}/util.zsh"

# util::repo_dir()を使ってパスを取得（SCRIPT_DIRをexportしてutil::repo_dir()で使えるようにする）
export SCRIPT_DIR
DOTFILES_DIR="$(util::repo_dir)"

util::info "Starting dotfiles installation..."

for script in ${DOTFILES_DIR}/setup/install/*.zsh; do
  if [[ -f "${script}" ]]; then
    if [[ ${FORCE} = 1 ]] || util::is_ci; then
      . "${script}"
    else
      util::confirm "install $(basename ${script})?"
      if [[ $? = 0 ]]; then
        . "${script}"
      fi
    fi
  fi
done

util::info "Installation completed successfully!"
util::info "Please restart your terminal to apply changes."