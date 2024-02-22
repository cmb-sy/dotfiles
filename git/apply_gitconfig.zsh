#!/bin/bash

echo  "Create .gitconfig links..."

ln -sfnv "${HOME}/dotfiles/git/.gitconfig" "${HOME}/.gitconfig"

echo "complete"
