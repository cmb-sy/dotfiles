# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# ------------------------------
# Load zplug
# ------------------------------
source ~/dotfiles/.zplugs.zsh
# --------------------------------------------------------------------
# command Settings
# -------------------------------------------------------------------
# zsh-syntax-highlighting
# $ brew install zsh-syntax-highlighting
source /usr/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# brew install zsh-autosuggestions
# source /usr/local/share/zsh-autosuggestions/zsh-autosuggestions.zsh
