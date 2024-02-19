# --------------------------------------------------------------------
# Executing this zsh file can load plugins, apply vscode settings, and apply key binding settings.
# --------------------------------------------------------------------

# setting.json
# cp ~/dotfiles/vscode/settings.json_with_comments.rb ~/dotfiles/vscode/settings.json

# file_path="path/to/your/file.txt"
# if [ -e "$file_path" ]; then
#     echo "File exists. Deleting..."
#     rm "$file_path"
#     echo "File deleted."
# else
#     echo "File does not exist."
# fi

# sed -i '' 's/\/\/.*//' ~/dotfiles/vscode/settings.json # //を含む行を削除して上書き
# rm -rf VSCODE_SETTING_DIR/settings.json
# ln -s ~/dotfiles/vscode/settings.json ~/Library/Application\ Support/Code/User/settings.json

# keybindinds.json
# cp ~/dotfiles/vscode/keybindings.json_with_comment.rb ~/dotfiles/vscode/keybindings.json
# sed -i '' 's/\/\/.*//' ~/dotfiles/vscode/keybindings.json
# rm -rf VSCODE_SETTING_DIR/keybindings.json
# ln -s ~/dotfiles/vscode/keybindings.json VSCODE_SETTING_DIR/keybindings.json


# extensions
extension_list=()
while IFS= read -r line; do
  extension_list+=("$line")
done < "/Users/snakashima/dotfiles/vscode/extensions.zsh"

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
