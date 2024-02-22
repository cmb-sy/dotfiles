# -------------------------------------------------------------------
# Customize Zsh's behavior to enable efficient command
# -------------------------------------------------------------------
setopt hist_ignore_dups
setopt hist_no_store
setopt share_history
setopt auto_list
setopt auto_menu


# -------------------------------------------------------------------
# Load zplug
# -------------------------------------------------------------------
source ~/dotfiles/zsh/.zplugs.zsh

# -------------------------------------------------------------------
# command Settings
# -------------------------------------------------------------------
# zsh-syntax-highlighting
# brew install zsh-syntax-highlighting
source /usr/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# brew install zsh-autosuggestions
source /usr/local/share/zsh-autosuggestions/zsh-autosuggestions.zsh


# -------------------------------------------------------------------
# Load sheldon
# -------------------------------------------------------------------
eval "$(sheldon source)"

# -------------------------------------------------------------------
# Load functions
# -------------------------------------------------------------------
source ${HOME}/.functions.zsh

# -------------------------------------------------------------------
# Load aliases
# -------------------------------------------------------------------
source ${HOME}/.aliases
