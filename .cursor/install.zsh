#!/bin/zsh
# Cursor 拡張機能をインストール（VSCode と同じ .vscode/extensions.zsh を参照）
CURSOR_DIR="${0:A:h}"
REPO_DIR="${CURSOR_DIR:h}"
source "${REPO_DIR}/setup/util.zsh"

util::info "Installing Cursor extensions (same list as VSCode)..."

EXTENSIONS_FILE="${REPO_DIR}/.vscode/extensions.zsh"
[[ ! -f "$EXTENSIONS_FILE" ]] && { util::warning "Not found: $EXTENSIONS_FILE"; return 1; }

while IFS= read -r line; do
  [[ -z "$line" || "$line" =~ ^# ]] && continue
  cursor --install-extension "${line%% *}" 2>/dev/null || true
done < "$EXTENSIONS_FILE"

util::info "Cursor extensions done."
