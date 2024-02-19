# --------------------------------------------------------------------
# Executing this zsh file can load plugins, apply vscode settings, and apply key binding settings.
# --------------------------------------------------------------------

#!/bin/bash
DOTFILE_VSCODE_SETTING_FILE="${HOME}/dotfiles/vscode/settings.json"
DOTFILE_VSCODE_KEYBINDING_FILE="${HOME}/dotfiles/vscode/keybindings.json"
VSCODE_SETTING_FILE="${HOME}/Library/Application Support/Code/User/settings.json"

if [ -e $VSCODE_SETTING_FILE ]; then  # whether exist or not exist
    rm $VSCODE_SETTING_FILE
    echo "VSCODE_SETTING_FILE deleted."
else
    echo "File does not exist."
fi

# setting.json
cp "${HOME}/dotfiles/vscode/settings.json_with_comments.rb" "$DOTFILE_VSCODE_SETTING_FILE"
sed -i '' 's/\/\/.*//' $DOTFILE_VSCODE_SETTING_FILE # //を含む行を削除して上書き
ln -s $DOTFILE_VSCODE_SETTING_FILE $VSCODE_SETTING_FILE

# keybindinds.json
# cp ~/dotfiles/vscode/keybindings.json_with_comment.rb ~/dotfiles/vscode/keybindings.json
# sed -i '' 's/\/\/.*//' ~/dotfiles/vscode/ç
# rm -rf VSCODE_SETTING_DIR/keybindings.json
# ln -s ~/dotfiles/vscode/keybindings.json VSCODE_SETTING_DIR/keybindings.json


# extensions
# extension_list=()
# while IFS= read -r line; do
#   extension_list+=("$line")
# done < "${HOME}/dotfiles/vscode/extensions.zsh"

# # confirm extension_list
# # for extension in "${extension_list[@]}"; do
# #   echo "$extension"
# # done

# if type code &>/dev/null; then
#   for extension in ${extension_list[@]}; do
#     code --install-extension ${extension}
#   done
# else
#   VSCODE_PATH_COMMAND="Shell Command: Install 'code' command in PATH"
#   echo 'Skipped install vscode extension.'
#   echo "Require run \"${VSCODE_PATH_COMMAND}\" in vscode!"
# fi
