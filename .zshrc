#!/bin/zsh

# ----------------------------------------------------------
# WezTerm
# ----------------------------------------------------------
if [[ "$TERM_PROGRAM" == "WezTerm" ]]; then
  # Strip trailing "true" so it is not printed to the terminal
  source <(sed '/^true$/d' "/Applications/WezTerm.app/Contents/Resources/wezterm.sh") 2>/dev/null
fi

# ----------------------------------------------------------
# Ghostty
# ----------------------------------------------------------
if [[ -n "${GHOSTTY_RESOURCES_DIR}" ]] && [[ -f "${GHOSTTY_RESOURCES_DIR}/shell-integration/zsh/ghostty-integration" ]]; then
  source "${GHOSTTY_RESOURCES_DIR}/shell-integration/zsh/ghostty-integration"
fi

# ----------------------------------------------------------
# Basic configuration
# ----------------------------------------------------------
ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets pattern cursor)

# ----------------------------------------------------------
# Zsh options
# ----------------------------------------------------------
# History
setopt hist_ignore_dups     # Drop consecutive duplicates
setopt hist_no_store        # Do not store the `history` command itself
setopt share_history        # Share history across sessions
setopt hist_reduce_blanks   # Strip extra spaces before saving
setopt hist_ignore_space    # Ignore commands that start with a space

# Completion
setopt auto_list            # List choices on ambiguous completion
setopt auto_menu            # Tab cycles through menu completions
setopt auto_param_slash     # Append / after directory names
setopt auto_param_keys      # Auto-insert matching brackets/quotes
setopt list_packed          # Compact completion lists
setopt list_types           # Show file type suffixes in listings

# Directory navigation
setopt auto_cd              # `dirname` alone runs `cd dirname`
setopt auto_pushd           # Make `cd` push the old directory onto the stack
setopt pushd_ignore_dups    # Do not push duplicate directories

# Misc
setopt correct              # Offer spelling corrections for commands
setopt no_beep              # No beep on errors
setopt interactive_comments # Allow `#` comments on the command line

# ----------------------------------------------------------
# Completion styling
# ----------------------------------------------------------
autoload -Uz compinit && compinit
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'       # Case-insensitive
zstyle ':completion:*:default' menu select=2              # Arrow-key menu
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"   # Colored listings

# ----------------------------------------------------------
# fzf (fuzzy directory, history, file insert)
# ----------------------------------------------------------
if command -v fzf &>/dev/null; then
  # Prefer fd over find for Alt+C / Ctrl+T when available
  if command -v fd &>/dev/null; then
    export FZF_ALT_C_COMMAND='fd --type d --hidden --follow -E .git -E node_modules .'
    export FZF_CTRL_T_COMMAND='fd --type f --hidden --follow -E .git -E node_modules .'
  fi
  # Alt+C: fuzzy cd / Ctrl+R: history / Ctrl+T: insert file path
  if [[ -f "${HOMEBREW_PREFIX:=$(brew --prefix 2>/dev/null)}/opt/fzf/shell/key-bindings.zsh" ]]; then
    source "${HOMEBREW_PREFIX}/opt/fzf/shell/key-bindings.zsh"
  fi
fi

# ----------------------------------------------------------
# Zsh plugins (sheldon) and prompt (starship)
# ----------------------------------------------------------
eval "$(sheldon source)"
eval "$(starship init zsh)"


# ----------------------------------------------------------
# Dotfiles extras (functions first, then aliases — Claude helpers live in .aliases.sh)
# ----------------------------------------------------------
if [[ -f "${DOTFILES:-${HOME}/dotfiles}/.function.zsh" ]]; then
  source "${DOTFILES:-${HOME}/dotfiles}/.function.zsh"
fi

if [[ -f "${DOTFILES:-${HOME}/dotfiles}/.aliases.sh" ]]; then
  source "${DOTFILES:-${HOME}/dotfiles}/.aliases.sh"
fi

# Default Claude Code account: company (~/.claude symlink + CLAUDE_CONFIG_DIR for new shells)
if [[ -o interactive ]] && typeset -f claude-use-work >/dev/null 2>&1; then
  claude-use-work
fi

# ----------------------------------------------------------
# PATH
# ----------------------------------------------------------
export PATH="${HOME}/.claude/local:$PATH"
export PATH="/opt/homebrew/bin:$PATH"
export PATH="/usr/local/bin:$PATH"
. "/Users/snakashima/.deno/env"
