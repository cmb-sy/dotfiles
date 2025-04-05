#!/bin/zsh

SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
source "${SCRIPT_DIR}/../util.zsh"

util::info "${YELLOW}Starting brew setup...${NC}"

export HOMEBREW_NO_AUTO_UPDATE=1

formulas=(
    fzf
    git
    zsh
    yarn
    sheldon
    starship
    uv
)

brew upgrade

for formula in "${formulas[@]}"; do
    brew install "${formula}"
done

util::info "${GREEN}Homebrew setup completed!${NC}" 
