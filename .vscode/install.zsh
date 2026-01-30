#!/bin/zsh

VSCODE_DIR="${0:A:h}"
REPO_DIR="${VSCODE_DIR:h}"
source "${REPO_DIR}/setup/util.zsh"

util::info "Installing VSCode extensions..."

while IFS= read -r line; do
  [[ -z "$line" || "$line" =~ ^# ]] && continue
  code --install-extension "${line%% *}" 2>/dev/null || true
done < "${VSCODE_DIR}/extensions.zsh"
