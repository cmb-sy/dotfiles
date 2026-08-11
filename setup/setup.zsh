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
# Link manifest
#
# Every link that is not produced by one of the globs below lives here, so the
# exceptions are visible as data instead of as scattered special cases.
# One line per link: "<src relative to repo>|<dst>|<mode>"
#   dir  = link the directory itself
#   file = link a single file (the destination directory also holds runtime
#          state, so it cannot be linked as a whole)
#----------------------------------------------------------
LINKS=(
  # reproduces alias / init.templatedir (distributes pre-commit hooks) on new machines
  "git/.gitconfig|${HOME}/.gitconfig|file"
  "karabiner|${HOME}/.config/karabiner|dir"
  # herdr writes logs/sockets/session.json next to its config
  "terminal/herdr/config.toml|${HOME}/.config/herdr/config.toml|file"
  # This is a global pin, and the name matters: mise auto-loads mise/config.toml,
  # .mise/config.toml and .config/mise/config.toml from a project directory. Any
  # of those makes every mise call inside this repo fail as untrusted, which drops
  # python3 back to the Xcode interpreter -- the one setup refuses.
  "setup/mise-config.toml|${HOME}/.config/mise/config.toml|file"
  ".vscode/settings.json|${HOME}/Library/Application Support/Code/User/settings.json|file"
  ".vscode/settings.json|${HOME}/Library/Application Support/Cursor/User/settings.json|file"
  # Cursor reads the same skills as Claude
  "claude/skills|${HOME}/.cursor/skills|dir"
)

# Apps create a real config dir on first launch (Karabiner does). Retire it, or
# util::link would refuse and the config would silently never apply.
link::retire_real_dir() {
  local dst="$1"
  if [[ -d "${dst}" && ! -L "${dst}" ]]; then
    mv "${dst}" "${dst}.bak.$(date +%s)"
    util::info "Moved aside real directory: ${dst} → ${dst}.bak.*"
  fi
}

link::from_manifest() {
  local entry src dst mode abs
  for entry in ${LINKS[@]}; do
    src="${entry%%|*}"
    dst="${entry#*|}"
    mode="${dst##*|}"
    dst="${dst%|*}"
    abs="${DOTFILES_DIR}/${src}"
    if [[ "${mode}" == "dir" && ! -d "${abs}" ]]; then
      util::warning "Skip ${src}: not a directory (mode dir)"
      continue
    fi
    if [[ "${mode}" == "file" && ! -f "${abs}" ]]; then
      util::warning "Skip ${src}: not a file (mode file)"
      continue
    fi
    if [[ "${mode}" != "dir" && "${mode}" != "file" ]]; then
      util::warning "Skip ${src}: unknown link mode '${mode}'"
      continue
    fi
    mkdir -p "${dst:h}"
    link::retire_real_dir "${dst}"
    util::link "${abs}" "${dst}"
  done
}

#----------------------------------------------------------
# Create symbolic links for shell dotfiles
#
# Explicit list only: globbing `*` missed hidden files (.zshrc etc.) and
# wrongly linked Brewfile/git/macos into $HOME, breaking git.
#----------------------------------------------------------
HOME_DOTFILES=(.zshrc .zshenv .aliases.sh .function.zsh .gitignore_global)

for name in ${HOME_DOTFILES[@]}; do
  util::link "${DOTFILES_DIR}/${name}" "${HOME}/${name}"
done

#----------------------------------------------------------
# Cleanup: remove wrong symlinks a previous glob-based version created in $HOME
# (~/.git in particular breaks git). Delete only symlinks pointing into this repo.
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
# Machine-local git overrides live outside the repo, so .gitconfig's
# `[include] path = ~/.gitconfig.local` has a file to resolve.
#----------------------------------------------------------
[[ -f "${HOME}/.gitconfig.local" ]] || touch "${HOME}/.gitconfig.local"

#----------------------------------------------------------
# .config symlinks
#----------------------------------------------------------
mkdir -p "${HOME}/.config"

for name in ${DOTFILES_DIR}/.config/*; do
  name="$(basename "${name}")"
  # karabiner is a manifest entry (source is the top-level karabiner/); skip it
  # here so this glob cannot double-link an untracked runtime dir.
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

# ~/.claude → ~/.claude-work directory symlink. A real ~/.claude is retired
# first: otherwise the per-asset links below land in an inactive directory and
# setup looks like it succeeded while none of the config applies.
link::retire_real_dir "${HOME}/.claude"
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
  # herdr cannot be bulk-symlinked as a whole directory; it is a manifest entry.
  [[ "${name}" == "herdr" ]] && continue
  util::link "${DOTFILES_DIR}/terminal/${name}" "${HOME}/.config/${name}"
done

#----------------------------------------------------------
# Everything the globs above cannot express: see LINKS at the top
#----------------------------------------------------------
link::from_manifest

# Karabiner needs approvals no script can grant.
if [[ -L "${HOME}/.config/karabiner" ]]; then
  util::warning "Manual step (cannot be scripted): launch Karabiner-Elements once and grant:"
  util::warning "  - the driver/system extension approval it prompts for on first launch"
  util::warning "  - Input Monitoring (System Settings > Privacy & Security > Input Monitoring)"
  util::warning "  Without these, Caps Lock -> Handy voice input silently does nothing."
fi

#----------------------------------------------------------
# Run installation scripts
#----------------------------------------------------------
FORCE=1
. "${DOTFILES_DIR}/setup/install.zsh"

#----------------------------------------------------------
util::info "Installation completed! Please restart terminal."
