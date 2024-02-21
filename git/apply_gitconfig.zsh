#!/bin/bash
GITCONFIG_FILE="${HOME}/.gitconfig"

if true; then  # whether exist or not exist
    rm "$GITCONFIG_FILE"
    echo "GITCONFIG_FILE deleted."
else
    echo "GITCONFIG_FILE does not exist."
fi

ln -s "${HOME}/dotfiles/git/.gitconfig" "$GITCONFIG_FILE"
echo "source command complete"
∏
