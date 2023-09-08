PATH=/bin:/usr/bin:/usr/local/bin:${PATH}

# condaの設定
__conda_setup="$('~/miniconda3/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "~/miniconda3/etc/profile.d/conda.sh" ]; then
        . "~/miniconda3/etc/profile.d/conda.sh"
    else
        export PATH="/Users/nakashima/miniconda3/bin:$PATH"
    fi
fi
unset __conda_setup
