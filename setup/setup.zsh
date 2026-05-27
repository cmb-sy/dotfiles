#!/bin/zsh

SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
source "${SCRIPT_DIR}/util.zsh"

export SCRIPT_DIR
DOTFILES_DIR="$(util::repo_dir)"

#----------------------------------------------------------
# Clone or update dotfiles
#----------------------------------------------------------
if [[ -z "${CI}" || "${CI}" != "true" ]]; then
  if [[ ! -e ${DOTFILES_DIR} ]]; then
    git clone --recursive https://github.com/cmb-sy/dotfiles.git ${DOTFILES_DIR}
  else
    (cd ${DOTFILES_DIR} && git pull)
  fi
fi

cd ${DOTFILES_DIR}

#----------------------------------------------------------
# Create symbolic links for dotfiles (dot-prefixed files)
#----------------------------------------------------------
for name in *; do
  if [[ ${name} != 'setup' ]] && [[ ${name} != 'README.md' ]] && [[ ${name} != 'terminal' ]] && [[ ${name} != 'tmux' ]]; then
    if [[ -L ${HOME}/.${name} ]]; then
      unlink ${HOME}/.${name}
    fi
    ln -sfv ${PWD}/${name} ${HOME}/.${name}
  fi
done

#----------------------------------------------------------
# .config symlinks
#----------------------------------------------------------
mkdir -p ${HOME}/.config

for name in ${DOTFILES_DIR}/.config/*; do
  name="$(basename ${name})"
  if [[ -L ${HOME}/.config/${name} ]]; then
    unlink ${HOME}/.config/${name}
  fi
  ln -sfv ${DOTFILES_DIR}/.config/${name} ${HOME}/.config/${name}
done


chmod +x ${DOTFILES_DIR}/claude/statusline.sh 2>/dev/null

#----------------------------------------------------------
# Claude Code (~/.claude → ~/.claude-work and per-asset symlinks)
#
# Structure on disk:
#   ~/.claude            → ~/.claude-work (directory symlink)
#   ~/.claude-work/      ← actual working directory; preserves runtime state
#     ├── CLAUDE.md      → dotfiles/claude/CLAUDE.md
#     ├── agents/        → dotfiles/claude/agents
#     ├── hooks/         → dotfiles/claude/hooks
#     ├── settings.json  → dotfiles/claude/settings.json
#     ├── skills/        → dotfiles/claude/skills
#     ├── statusline.sh  → dotfiles/claude/statusline.sh
#     └── (runtime files: .claude.json, cache/, file-history/, backups/, ...)
#----------------------------------------------------------
mkdir -p ${HOME}/.claude-work

# ~/.claude → ~/.claude-work directory symlink
# Use -h to avoid following an existing symlink when checking
if [[ -L ${HOME}/.claude ]]; then
  unlink ${HOME}/.claude
elif [[ -e ${HOME}/.claude ]]; then
  util::warning "~/.claude exists and is not a symlink; skipping (move or remove manually)"
fi
if [[ ! -e ${HOME}/.claude ]]; then
  ln -sfv ${HOME}/.claude-work ${HOME}/.claude
fi

# Per-asset symlinks inside ~/.claude-work
for name in CLAUDE.md agents hooks settings.json skills statusline.sh; do
  src=${DOTFILES_DIR}/claude/${name}
  dst=${HOME}/.claude-work/${name}
  if [[ ! -e ${src} ]]; then
    util::warning "Skip claude/${name}: source not found at ${src}"
    continue
  fi
  if [[ -L ${dst} ]]; then
    unlink ${dst}
  elif [[ -e ${dst} ]]; then
    util::warning "${dst} exists and is not a symlink; skipping (move or remove manually)"
    continue
  fi
  ln -sfv ${src} ${dst}
done

#----------------------------------------------------------
# WezTerm
#----------------------------------------------------------
for name in ${DOTFILES_DIR}/terminal/*; do
  name="$(basename ${name})"
  if [[ -L ${HOME}/.config/${name} ]]; then
    unlink ${HOME}/.config/${name}
  fi
  ln -sfv ${DOTFILES_DIR}/terminal/${name} ${HOME}/.config/${name}
done

#----------------------------------------------------------
# VSCode Settings
#----------------------------------------------------------
mkdir -p "${HOME}/Library/Application Support/Code/User"
ln -sfv ${DOTFILES_DIR}/.vscode/settings.json "${HOME}/Library/Application Support/Code/User/settings.json"

#----------------------------------------------------------
# Cursor Settings
#----------------------------------------------------------
mkdir -p "${HOME}/Library/Application Support/Cursor/User"
ln -sfv ${DOTFILES_DIR}/.vscode/settings.json "${HOME}/Library/Application Support/Cursor/User/settings.json"

#----------------------------------------------------------
# Run installation scripts
#----------------------------------------------------------
FORCE=1
. ${DOTFILES_DIR}/setup/install.zsh

#----------------------------------------------------------
util::info "Installation completed! Please restart terminal."
