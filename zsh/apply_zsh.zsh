
if [ -e "${HOME}/.zshrc" ]; then  # whether exist or not exist
    rm ${HOME}/.zshrc
    echo "VSCODE_KEYBINDING_FILE deleted."
else
    echo "VSCODE_KEYBINDING_FILE does not exist."
fi

ln -s ${HOME}/dotfiles/.zshrc ${HOME}/.zshrc
