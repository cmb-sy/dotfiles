#!/bin/zsh
# Git installation and configuration

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
source "${SCRIPT_DIR}/../util.zsh"

# Define dotfiles directory
DOTFILES_DIR="$(util::repo_dir)"
GIT_DIR="${DOTFILES_DIR}/git"

util::info "Setting up Git..."

# Check if directory exists
if [[ ! -d "${GIT_DIR}" ]]; then
    util::error "Git directory not found: ${GIT_DIR}"
    exit 1
fi

# Install Git if not installed
if ! util::has git; then
    util::info "Installing Git..."
    brew install git
fi

# Create symlinks for Git configuration
util::info "Creating Git configuration symlinks..."
util::symlink "${GIT_DIR}/.gitconfig" "${HOME}/.gitconfig"

# Configure Git user if not already set
if ! git config --global user.name &>/dev/null; then
    if ! util::is_ci; then
        util::info "Configuring Git user..."
        read "?Enter your Git username: " username
        read "?Enter your Git email: " email
        git config --global user.name "$username"
        git config --global user.email "$email"
    else
        util::info "Running in CI environment, setting default Git user..."
        git config --global user.name "CI User"
        git config --global user.email "ci-user@example.com"
    fi
fi

# Configure Git defaults
util::info "Configuring Git defaults..."
git config --global init.defaultBranch main
git config --global pull.rebase false
git config --global core.editor "vim"

util::info "Git setup completed successfully!" 