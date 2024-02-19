#!/bin/bash
# Executing this zsh file can load plugins, apply vscode settings, and apply key binding settings.

# --------------------------------------------------------------------
# setting.json
# --------------------------------------------------------------------
DOTFILE_VSCODE_SETTING_FILE="${HOME}/dotfiles/vscode/settings.json"
VSCODE_SETTING_FILE="${HOME}/Library/Application Support/Code/User/settings.json"
if [ -e $VSCODE_SETTING_FILE ]; then  # whether exist or not exist
    rm $VSCODE_SETTING_FILE
    echo "VSCODE_SETTING_FILE deleted."
else
    echo "VSCODE_SETTING_FILE does not exist."
fi

cp "${HOME}/dotfiles/vscode/settings.json_with_comments.rb" "$DOTFILE_VSCODE_SETTING_FILE"
sed -i '' 's/\/\/.*//' $DOTFILE_VSCODE_SETTING_FILE # //を含む行を削除して上書き
ln -s $DOTFILE_VSCODE_SETTING_FILE $VSCODE_SETTING_FILE

# --------------------------------------------------------------------
# keybindinds.json
# --------------------------------------------------------------------
VSCODE_KEYBINDING_FILE="${HOME}/Library/Application Support/Code/User/settings.json"
DOTFILE_VSCODE_KEYBINDING_FILE="${HOME}/dotfiles/vscode/keybindings.json"

if [ -e $VSCODE_KEYBINDING_FILE ]; then  # whether exist or not exist
    rm $VSCODE_KEYBINDING_FILE
    echo "VSCODE_KEYBINDING_FILE deleted."
else
    echo "VSCODE_KEYBINDING_FILE does not exist."
fi

cp "${HOME}/dotfiles/vscode/settings.json_with_comments.rb" "$DOTFILE_VSCODE_KEYBINDING_FILE"
sed -i '' 's/\/\/.*//' $DOTFILE_VSCODE_KEYBINDING_FILE # //を含む行を削除して上書き
ln -s $DOTFILE_VSCODE_KEYBINDING_FILE $VSCODE_KEYBINDING_FILE

# --------------------------------------------------------------------
# extensions
# --------------------------------------------------------------------
extension_list=()
while IFS= read -r line; do
  extension_list+=("$line")
done < "${HOME}/dotfiles/vscode/extensions.zsh"

# confirm extension_list
# for extension in "${extension_list[@]}"; do
#   echo "$extension"
# done

if type code &>/dev/null; then
  for extension in ${extension_list[@]}; do
    code --install-extension ${extension}
  done
else
  VSCODE_PATH_COMMAND="Shell Command: Install 'code' command in PATH"
  echo 'Skipped install vscode extension.'
  echo "Require run \"${VSCODE_PATH_COMMAND}\" in vscode!"
fi
