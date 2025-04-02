#!/bin/zsh

# スクリプトのあるディレクトリを取得する
SCRIPT_DIR="${HOME}/.dotfiles/setup"
source "${SCRIPT_DIR}/util.zsh"

util::info "dotfilesのインストールを開始します..."

for script in $(\ls ${HOME}/.dotfiles/setup/install); do   
  util::confirm "install ${script}?"
  if [[ $? = 0 ]]; then
    . ${HOME}/.dotfiles/setup/install/${script}
  fi
done

util::info "インストールが正常に完了しました！"
util::info "変更を適用するためにターミナルを再起動してください。"