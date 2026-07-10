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

  # Claude Code tab indicator: ⚡ while running, ✅/❌ on completion
  typeset -gi _claude_running=0
  typeset -gi _claude_exit=0

  _claude_tab_preexec() {
    if [[ "$1" == claude* ]]; then
      _claude_running=1
      printf '\e]2;⚡ CLAUDE CODE\a'
    fi
  }

  _claude_tab_precmd() {
    local s=$?
    (( _claude_running )) && _claude_exit=$s
    return $s
  }

  # Deferred setup: runs after Ghostty's deferred init on the first precmd
  _claude_tab_setup() {
    preexec_functions+=(_claude_tab_preexec)
    precmd_functions+=(_claude_tab_precmd)

    # Chain zle-line-init — fires AFTER all precmd hooks, so it overrides
    # Ghostty's title reset when Claude Code just finished
    (( $+widgets[zle-line-init] )) && zle -A zle-line-init _orig_zle_line_init_ct
    _claude_tab_line_init() {
      (( $+widgets[_orig_zle_line_init_ct] )) && zle _orig_zle_line_init_ct
      if (( _claude_running )); then
        if (( _claude_exit == 0 )); then
          printf '\e]2;✅ CLAUDE CODE\a'
        else
          printf '\e]2;❌ CLAUDE CODE\a'
        fi
        _claude_running=0
      fi
    }
    zle -N zle-line-init _claude_tab_line_init

    precmd_functions=(${precmd_functions:#_claude_tab_setup})
  }
  precmd_functions+=(_claude_tab_setup)
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
    # No --follow and exclude Library: run from $HOME these otherwise descend into
    # ~/Library/CloudStorage/OneDrive (network-backed on-demand files) and hang.
    export FZF_ALT_C_COMMAND='fd --type d --hidden -E .git -E node_modules -E Library .'
    export FZF_CTRL_T_COMMAND='fd --type f --hidden -E .git -E node_modules -E Library .'
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
# PATH (before .aliases.sh so `command -v claude` sees the CLI)
# claude は Homebrew (/opt/homebrew/bin/claude) に一本化。他の場所にインストールしないこと
#
# .zshenv と同じ prepend の再実行 — 重複ではない。login shell では
# /etc/zprofile の path_helper が .zshenv 適用後に PATH を並べ替えるため、
# ここで再 prepend して優先順位を復元する。変更時は .zshenv と揃えること。
# ----------------------------------------------------------
export PATH="/opt/homebrew/bin:$PATH"
export PATH="/usr/local/bin:$PATH"
export PATH="${DOTFILES:-${HOME}/dotfiles}/bin:$PATH"   # handy-switch, dev, ai-format, help_key
export PATH="$HOME/.local/bin:$PATH"                    # slackcli, tmux-sessionizer

# mise (runtime version manager) — must come after PATH so mise shims take priority
eval "$(mise activate zsh)"

# ----------------------------------------------------------
# Dotfiles extras (functions first, then aliases — Claude helpers live in .aliases.sh)
# ----------------------------------------------------------
if [[ -f "${DOTFILES:-${HOME}/dotfiles}/.function.zsh" ]]; then
  source "${DOTFILES:-${HOME}/dotfiles}/.function.zsh"
fi

if [[ -f "${DOTFILES:-${HOME}/dotfiles}/.aliases.sh" ]]; then
  source "${DOTFILES:-${HOME}/dotfiles}/.aliases.sh"
fi
# ----------------------------------------------------------
# bun (curl installer 製、Homebrew 管理外) / maestro (同じく管理外)
# ----------------------------------------------------------
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"   # bun completions
export PATH=$PATH:$HOME/.maestro/bin
