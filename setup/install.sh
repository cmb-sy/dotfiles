#!/bin/bash
# Main installation script for dotfiles

# Exit on error
set -e

# Source utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/util.zsh"

util::info "Starting dotfiles installation..."

# Check if running on macOS
if ! util::is_mac; then
    util::error "This script is only for macOS"
    exit 1
fi

# Create necessary directories
util::info "Creating necessary directories..."
util::mkdir "${HOME}/.config"
util::mkdir "${HOME}/.config/cursor/rules"
util::mkdir "${HOME}/Library/Application Support/Code/User"
util::mkdir "${HOME}/Library/LaunchAgents"

# Define dotfiles directory
DOTFILES_DIR="$(util::repo_dir)"

# Run all installation scripts or ask for confirmation
if [[ ${FORCE} = 1 ]] || util::is_ci; then
    util::info "Running all installation scripts in force mode..."
    for script in "${SCRIPT_DIR}/install"/*.zsh; do
        script_name="$(basename "${script}")"
        util::info "Running ${script_name}..."
        zsh "${script}"
    done
else
    # Ask for each installation script
    for script in "${SCRIPT_DIR}/install"/*.zsh; do
        script_name="$(basename "${script}")"
        util::confirm "Run ${script_name}?"
        if [[ $? = 0 ]]; then
            util::info "Running ${script_name}..."
            zsh "${script}"
        else
            util::warning "Skipping ${script_name}..."
        fi
    done
fi

util::info "Installation completed successfully!"
util::info "Please restart your terminal to apply all changes."

