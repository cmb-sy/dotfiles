# -----------------------------------------------------------
# Formula
# -----------------------------------------------------------
brew 'bats-core'
brew 'coreutils'
brew 'fd'
brew 'fzf'
brew 'sheldon'
brew 'starship'
brew 'gh'
brew 'zsh'
brew 'uv'
brew 'yarn'
brew 'git'
brew 'lazygit'
brew 'neovim'
# nvim-treesitter's main branch compiles parsers with this CLI; without it a
# fresh machine gets no treesitter highlighting at all.
brew 'tree-sitter-cli'
brew 'ripgrep'
brew 'bat'
brew 'mise'
brew 'tmux'
brew 'herdr'
brew 'jq'
brew 'tfenv'
tap 'manaflow-ai/cmux'

# -----------------------------------------------------------
# Cask
# -----------------------------------------------------------
cask 'google-chrome'
cask 'ghostty'
cask 'wezterm'
cask 'cmux'
cask 'cursor'
cask 'docker-desktop'
cask 'slack'
cask 'obsidian'
cask 'zoom'
cask 'notion'
# cask '1password'
cask 'claude'
cask 'claude-code@latest'
cask 'flux-app'
cask 'wireshark-app'
cask 'karabiner-elements'
# Voice input: Handy (local STT) + ollama (offline LLM post-processing server),
# and Typeless (GUI/cloud alternative). Switch between them via `voice-switch`.
# Cloud post-processing (opt-in via `voice-switch cloud`) targets Cerebras, which
# does not retain or train on request data:
#   https://support.cerebras.net/articles/1811589793-does-cerebras-retain-my-data
#   https://www.cerebras.ai/terms-of-service
cask 'handy'
cask 'ollama-app'
cask 'typeless'

# Fonts terminal/ghostty/config names. Without these the config points at
# families that do not exist, the OS falls back per glyph, and the characters
# the fallback cannot cover render as .notdef boxes.
#   HackGen  -- CJK, mapped by font-codepoint-map so Japanese stays monospaced
#   Monaspace -- the body font (Neon is one of its families)
#   FiraCode Nerd Font -- the icon glyphs the prompt uses
cask 'font-hackgen'
cask 'font-monaspace'
cask 'font-fira-code-nerd-font'
