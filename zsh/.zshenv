# Files that are always read when zsh is started
# --------------------------------------------------------------------
# General Settings
# --------------------------------------------------------------------
export LANG=en_US.UTF-8 
export LC_ALL=en_US.UTF-8
export TZ=Asia/Tokyo

# --------------------------------------------------------------------
# Editter Settings
# --------------------------------------------------------------------
export EDITOR=vim
export PAGER=lv

# --------------------------------------------------------------------
# History Settings
# --------------------------------------------------------------------
export HISTFILE="${HOME}/.zsh-history"
export HISTSIZE=1000000
export SAVEHIST=1000000

# --------------------------------------------------------------------
# path setting
# --------------------------------------------------------------------
export PATH="/usr/local/bin:${PATH}"
export PATH="${HOME}/.asdf/bin:${PATH}"
export PATH="${HOME}/.asdf/shims:${PATH}"
export PATH="/opt/homebrew/bin:$PATH"

# --------------------------------------------------------------------
# conda setting
# --------------------------------------------------------------------
__conda_setup="$('~/miniconda3/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "~/miniconda3/etc/profile.d/conda.sh" ]; then
        . "~/miniconda3/etc/profile.d/conda.sh"
    else
        export PATH="~/miniconda3/bin:$PATH"
    fi
fi
unset __conda_setup

# --------------------------------------------------------------------
# Python Settings
# --------------------------------------------------------------------
export PATH="/usr/bin/python:$PATH"

