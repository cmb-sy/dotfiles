DOT_DIR="${HOME}/dotfiles"

echo  "Create zsh links ..."

ln -snfv "${DOT_DIR}/zsh/.zshenv" "${HOME}/.zshenv"
ln -snfv "${DOT_DIR}/zsh/.zshrc" "${HOME}/.zshrc"
ln -snfv "${DOT_DIR}/zsh/.aliases.sh" "${HOME}/.aliases"
ln -snfv "${DOT_DIR}/zsh/.function.zsh" "${HOME}/.function.zsh"

# sheldon init --shell zsh
# 既存のconfigファイルが存在しているためうまくシンボリックリンクが作成できない。先に消す必要がある。
rm -rf "${HOME}/.config"
ln -snfv "${DOT_DIR}/.config" "${HOME}/.config"
