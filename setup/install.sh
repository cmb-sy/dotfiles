#!/bin/bash
# Main installation script for dotfiles

# Exit on error
set -e

#!/bin/zsh

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

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Starting dotfiles installation...${NC}"

# Check if running on macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo -e "${RED}This script is only for macOS${NC}"
    exit 1
fi

# Define directories to create
declare -A dirs=(
    ["~/.config"]="config directory"
    ["~/.config/cursor/rules"]="cursor rules"
    ["~/Library/Application Support/Code/User"]="vscode config"
    ["~/Library/LaunchAgents"]="launch agents"
)

# Create necessary directories
echo -e "${YELLOW}Creating directories...${NC}"
for dir in "${!dirs[@]}"; do
    echo -e "${YELLOW}Creating ${dir} (${dirs[$dir]})...${NC}"
    mkdir -p "$dir"
done

# Define symlinks to create
declare -A symlinks=(
    ["../zsh/.zshrc"]="~/.zshrc"
    ["../zsh/.zshenv"]="~/.zshenv"
    ["../zsh/.aliases.sh"]="~/.aliases.sh"
    ["../zsh/.function.zsh"]="~/.function.zsh"
    ["../vscode/settings.json"]="~/Library/Application Support/Code/User/settings.json"
    ["../vscode/keybindings.json"]="~/Library/Application Support/Code/User/keybindings.json"
    ["../macos/system.enviroment.plist"]="~/Library/LaunchAgents/system.enviroment.plist"
    ["../git/.gitconfig"]="~/.gitconfig"
    ["../.config/starship.toml"]="~/.config/starship.toml"
    ["../.config/cursor/rules/assistant.mdc"]="~/.config/cursor/rules/assistant.mdc"
)

# Create symlinks
echo -e "${YELLOW}Creating symlinks...${NC}"
for src in "${!symlinks[@]}"; do
    echo -e "${YELLOW}Creating symlink: ${symlinks[$src]} -> ${src}...${NC}"
    ln -sf "$(pwd)/${src}" "${symlinks[$src]}"
done

# Run setup scripts
echo -e "${YELLOW}Running setup scripts...${NC}"
for script in setup_*.sh; do
    echo -e "${YELLOW}Running ${script}...${NC}"
    ./"$script"
done

echo -e "${GREEN}Installation completed successfully!${NC}"
echo -e "${YELLOW}Please restart your terminal to apply all changes.${NC}"
