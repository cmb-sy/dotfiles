#!/bin/bash
# Executing this zsh file can load plugins, apply vscode settings, and apply key binding settings.

# --------------------------------------------------------------------
# extensions
# --------------------------------------------------------------------
echo  "Download vscode extensions..."

extension_list=()
while IFS= read -r line; do
  extension_list+=("$line")
done < "${HOME}/dotfiles/vscode/extensions.zsh"

if type code &>/dev/null; then
  for extension in ${extension_list[@]}; do
    code --install-extension ${extension}
  done
else
  VSCODE_PATH_COMMAND="Shell Command: Install 'code' command in PATH"
  echo 'Skipped install vscode extension.'
  echo "Require run \"${VSCODE_PATH_COMMAND}\" in vscode!"
fi

echo  "Download complete"
# --------------------------------------------------------------------
# setting.json
# --------------------------------------------------------------------
echo  "Create vscode links ..."

DOTFILE_VSCODE_SETTING_FILE="${HOME}/dotfiles/vscode/settings.json"

cp "${HOME}/dotfiles/vscode/settings.json_with_comments.rb" "$DOTFILE_VSCODE_SETTING_FILE"
sed -i '' 's/\/\/.*//' $DOTFILE_VSCODE_SETTING_FILE # //を含む行を削除して上書き
ln -sfnv $DOTFILE_VSCODE_SETTING_FILE "${HOME}/Library/Application Support/Code/User/settings.json"

# --------------------------------------------------------------------
# keybindinds.json
# --------------------------------------------------------------------
DOTFILE_VSCODE_KEYBINDING_FILE="${HOME}/dotfiles/vscode/keybindings.json"

cp "${HOME}/dotfiles/vscode/keybindings.json_with_comment.rb" "$DOTFILE_VSCODE_KEYBINDING_FILE"
sed -i '' 's/\/\/.*//' $DOTFILE_VSCODE_KEYBINDING_FILE # //を含む行を削除して上書き
ln -sfnv $DOTFILE_VSCODE_KEYBINDING_FILE "${HOME}/Library/Application Support/Code/User/keybindings.json"

echo  "Create complete"
