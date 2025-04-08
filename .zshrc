#!/bin/zsh

# ----------------------------------------------------------
# Basic Configuration
# ----------------------------------------------------------
# Enable command highlighting
ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets pattern cursor)

# ----------------------------------------------------------
# Zsh
# ----------------------------------------------------------
# History related settings
setopt hist_ignore_dups     # Don't keep duplicated commands in history
setopt hist_no_store        # Don't store history command in history
setopt share_history        # Share history between sessions
setopt hist_reduce_blanks   # Remove extra spaces
setopt hist_ignore_space    # Don't store commands starting with space

# Completion related settings
setopt auto_list            # Show completion candidates
setopt auto_menu            # Cycle through completion candidates with tab
setopt auto_param_slash     # Add slash at the end of directory completion
setopt auto_param_keys      # Auto complete brackets and quotes
setopt list_packed          # Display completion candidates compactly
setopt list_types           # Show file types in completion candidates

# Directory movement
setopt auto_cd              # cd to directory by just typing its name
setopt auto_pushd           # Add directories to stack when cd
setopt pushd_ignore_dups    # Don't add duplicate directories to stack

# Others
setopt correct              # Correct command spelling
setopt no_beep              # No beep sound
setopt interactive_comments # Enable comments on command line

# ----------------------------------------------------------
# Completion Settings
# ----------------------------------------------------------
autoload -Uz compinit && compinit
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'       # Case insensitive completion
zstyle ':completion:*:default' menu select=2              # Select completion candidates with cursor
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"   # Colorize completion candidates

# ----------------------------------------------------------
# Zsh Plugin Management (sheldon) and Theme
# ----------------------------------------------------------
eval "$(sheldon source)"
eval "$(starship init zsh)"

# ----------------------------------------------------------
# Tmux settings
# ----------------------------------------------------------
bindkey -s '^T' 'tmux attach || tmux new-session\n'
bindkey -s '^B' 'tmux new-session\n'

if [ -n "$TMUX" ]; then
    tmux source-file ~/.tmux.conf 2>/dev/null
fi

# ----------------------------------------------------------
# Configuration Files
# ----------------------------------------------------------
source ${HOME}/dotfiles/.function.zsh
source ${HOME}/dotfiles/.aliases.sh
cp ${HOME}/dotfiles/.config/alacritty/alacritty.toml ${HOME}/.config/alacritty/alacritty.toml
git config --global core.excludesfile ~/.gitignore_global
