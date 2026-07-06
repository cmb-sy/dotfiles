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
# Create symbolic links for shell dotfiles
#
# 旧実装は `for name in *` で glob したが、zsh デフォルトで hidden file が
# 除外されるため .zshrc などが symlink されなかった。さらに Brewfile / git /
# macos などが ~/.Brewfile / ~/.git / ~/.macos に誤リンクされて
# git の挙動を壊す問題があった。
# 明示的にリストアップして、それ以外は触らない方針に変更する。
#----------------------------------------------------------
HOME_DOTFILES=(.zshrc .zshenv .aliases.sh .function.zsh .gitignore_global)

for name in ${HOME_DOTFILES[@]}; do
  src=${DOTFILES_DIR}/${name}
  dst=${HOME}/${name}
  if [[ ! -e ${src} ]]; then
    util::warning "Skip ${name}: source not found at ${src}"
    continue
  fi
  # symlink でも、別の場所を指していたり broken symlink でも貼り直す
  if [[ -L ${dst} ]]; then
    unlink ${dst}
  elif [[ -e ${dst} ]]; then
    util::warning "${dst} exists and is not a symlink; skipping (move or remove manually)"
    continue
  fi
  ln -sfv ${src} ${dst}
done

#----------------------------------------------------------
# Cleanup: 旧実装が作った誤った symlink を除去
#
# 旧 `for name in *` ループが Brewfile / bin / docs / git / macos を
# ~/.<name> へ symlink していた。これらは本来不要（特に ~/.git は git の
# 動作を壊す）なので、symlink である場合のみ削除する。
#----------------------------------------------------------
for legacy in .Brewfile .bin .docs .git .macos .claude-old; do
  target=${HOME}/${legacy}
  if [[ -L ${target} ]]; then
    link_target=$(readlink "${target}")
    if [[ "${link_target}" == "${DOTFILES_DIR}"* ]]; then
      unlink "${target}"
      util::info "Removed legacy symlink: ${target} → ${link_target}"
    fi
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
  elif [[ -e ${HOME}/.config/${name} ]]; then
    util::warning "${HOME}/.config/${name} exists and is not a symlink; skipping (move or remove manually)"
    continue
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
# Terminals (ghostty / wezterm / cmux): symlink each into ~/.config/<name>
#----------------------------------------------------------
for name in ${DOTFILES_DIR}/terminal/*; do
  name="$(basename ${name})"
  if [[ -L ${HOME}/.config/${name} ]]; then
    unlink ${HOME}/.config/${name}
  elif [[ -e ${HOME}/.config/${name} ]]; then
    util::warning "${HOME}/.config/${name} exists and is not a symlink; skipping (move or remove manually)"
    continue
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
