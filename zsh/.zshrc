# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# -------------------------------------------------------------------
# Customize Zsh's behavior to enable efficient command
# -------------------------------------------------------------------
setopt hist_ignore_dups
setopt hist_no_store
setopt share_history
setopt auto_list
setopt auto_menu

# -------------------------------------------------------------------
# Load sheldon
# -------------------------------------------------------------------
# sheldon init --shell zsh
eval "$(sheldon source)"

# -------------------------------------------------------------------
# Load functions
# -------------------------------------------------------------------
source ${HOME}/.function.zsh

# -------------------------------------------------------------------
# Load aliases
# -------------------------------------------------------------------
source ${HOME}/.aliases

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
source ~/.p10k.zsh
