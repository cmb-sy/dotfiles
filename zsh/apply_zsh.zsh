DOT_DIR="${HOME}/dotfiles/zsh"

echo  "Create zsh links ..."

ln -snfv "${DOT_DIR}/.zshenv" "${HOME}/.zshenv"
ln -snfv "${DOT_DIR}/.zshrc" "${HOME}/.zshrc"
# ln -snfv "${DOT_DIR}/.aliases.sh" "${HOME}/.aliases"
# ln -snfv "${DOT_DIR}/.functions.zsh" "${HOME}/.functions.zsh"

# sheldon init --shell zsh
ln -snfv "${DOT_DIR}/.config/sheldon/.plugin.toml" "${HOME}/.config/sheldon/plugins.toml"
