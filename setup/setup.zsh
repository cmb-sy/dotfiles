#!/bin/zsh

SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
source "${SCRIPT_DIR}/util.zsh"

export SCRIPT_DIR
DOTFILES_DIR="$(util::repo_dir)"

#----------------------------------------------------------
# Clone or update dotfiles
#----------------------------------------------------------
if [[ -z "${CI}" || "${CI}" != "true" ]]; then
  if [[ ! -e "${DOTFILES_DIR}" ]]; then
    git clone --recursive https://github.com/cmb-sy/dotfiles.git "${DOTFILES_DIR}"
  else
    (cd "${DOTFILES_DIR}" && git pull)
  fi
fi

cd "${DOTFILES_DIR}"

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
  util::link "${DOTFILES_DIR}/${name}" "${HOME}/${name}"
done

# git config: alias / init.templatedir(=pre-commit フック配布の起点) を新規マシンでも再現する。
# これまで手動 symlink 依存で setup に配線がなかった。
util::link "${DOTFILES_DIR}/git/.gitconfig" "${HOME}/.gitconfig"

#----------------------------------------------------------
# Cleanup: 旧実装が作った誤った symlink を除去
#
# 旧 `for name in *` ループが Brewfile / bin / docs / git / macos を
# ~/.<name> へ symlink していた。これらは本来不要（特に ~/.git は git の
# 動作を壊す）なので、symlink である場合のみ削除する。
#----------------------------------------------------------
for legacy in .Brewfile .bin .docs .git .macos .claude-old; do
  target="${HOME}/${legacy}"
  if [[ -L "${target}" ]]; then
    link_target="$(readlink "${target}")"
    if [[ "${link_target}" == "${DOTFILES_DIR}"* ]]; then
      unlink "${target}"
      util::info "Removed legacy symlink: ${target} → ${link_target}"
    fi
  fi
done

#----------------------------------------------------------
# .config symlinks
#----------------------------------------------------------
mkdir -p "${HOME}/.config"

for name in ${DOTFILES_DIR}/.config/*; do
  name="$(basename "${name}")"
  # karabiner は install.zsh が dotfiles/karabiner を ~/.config/karabiner へ直接
  # リンクする。この glob が未追跡の runtime dir を拾って二重リンクしないよう除外。
  [[ "${name}" == "karabiner" ]] && continue
  util::link "${DOTFILES_DIR}/.config/${name}" "${HOME}/.config/${name}"
done


chmod +x "${DOTFILES_DIR}/claude/statusline.sh" 2>/dev/null

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
mkdir -p "${HOME}/.claude-work"

# ~/.claude → ~/.claude-work directory symlink
util::link "${HOME}/.claude-work" "${HOME}/.claude"

# Per-asset symlinks inside ~/.claude-work
for name in CLAUDE.md agents hooks settings.json skills statusline.sh; do
  src="${DOTFILES_DIR}/claude/${name}"
  dst="${HOME}/.claude-work/${name}"
  util::link "${src}" "${dst}"
done

#----------------------------------------------------------
# Terminals (ghostty / wezterm / cmux): symlink each into ~/.config/<name>
#----------------------------------------------------------
for name in ${DOTFILES_DIR}/terminal/*; do
  name="$(basename "${name}")"
  # herdr writes runtime logs/sockets/session.json next to its config, so it
  # cannot be bulk-symlinked as a whole directory; handled separately below.
  [[ "${name}" == "herdr" ]] && continue
  util::link "${DOTFILES_DIR}/terminal/${name}" "${HOME}/.config/${name}"
done

#----------------------------------------------------------
# herdr: symlink config.toml only (its config dir also holds runtime
# logs/sockets/session.json, unlike the other terminal tools above)
#----------------------------------------------------------
if [[ -f "${DOTFILES_DIR}/terminal/herdr/config.toml" ]]; then
  mkdir -p "${HOME}/.config/herdr"
  dst="${HOME}/.config/herdr/config.toml"
  util::link "${DOTFILES_DIR}/terminal/herdr/config.toml" "${dst}"
fi

#----------------------------------------------------------
# VSCode Settings
#----------------------------------------------------------
mkdir -p "${HOME}/Library/Application Support/Code/User"
util::link "${DOTFILES_DIR}/.vscode/settings.json" "${HOME}/Library/Application Support/Code/User/settings.json"

#----------------------------------------------------------
# Cursor Settings
#----------------------------------------------------------
mkdir -p "${HOME}/Library/Application Support/Cursor/User"
util::link "${DOTFILES_DIR}/.vscode/settings.json" "${HOME}/Library/Application Support/Cursor/User/settings.json"

#----------------------------------------------------------
# Run installation scripts
#----------------------------------------------------------
FORCE=1
. "${DOTFILES_DIR}/setup/install.zsh"

#----------------------------------------------------------
util::info "Installation completed! Please restart terminal."
