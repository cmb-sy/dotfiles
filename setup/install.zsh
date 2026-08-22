#!/bin/zsh

SCRIPT_DIR="${0:A:h}"
REPO_DIR="${SCRIPT_DIR:h}"
source "${SCRIPT_DIR}/util.zsh"

#----------------------------------------------------------
# Linux (OCI server): delegate to the server installer
#----------------------------------------------------------
if [[ "$(uname -s)" == "Linux" ]]; then
  util::info "Linux detected: delegating to server/install.zsh"
  zsh "${REPO_DIR}/server/install.zsh"
  # return when sourced (setup.zsh does), exit when run directly
  return 0 2>/dev/null || exit 0
fi

util::info "Starting dotfiles installation..."

#----------------------------------------------------------
# Homebrew (Brewfile)
# CI installs formulas only: casks cannot be launch-tested there and
# downloading them blows the job's 60-minute timeout.
#----------------------------------------------------------
if util::confirm "Install packages from Brewfile?"; then
  BREWFILE="${REPO_DIR}/Brewfile"
  if util::is_ci; then
    BREWFILE="$(mktemp)"
    grep -vE '^cask ' "${REPO_DIR}/Brewfile" > "${BREWFILE}"
  fi
  HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1 \
    brew bundle --file="${BREWFILE}" --quiet
fi

#----------------------------------------------------------
# Language runtimes (setup/mise-config.toml pins the versions; setup links it
# to ~/.config/mise/config.toml)
#
# Must precede the python step: it decides which interpreter `python3` is.
#----------------------------------------------------------
if util::confirm "Install the runtimes mise pins (python, node, deno)?"; then
  if util::has mise; then
    # Failure here is not cosmetic: the python step below then falls back to an
    # interpreter it cannot install into, so say what breaks.
    mise install \
      || util::warning "mise install failed; pygments/pyyaml cannot be installed and the tests that need them will skip."
  else
    util::warning "mise not found; skipping runtimes (install the Brewfile first)."
  fi
fi

#----------------------------------------------------------
# Python packages (tests + bin/highlight-code)
#
# Homebrew cannot express these: its pygments formula is a private virtualenv
# exposing only the pygmentize CLI, and pyyaml has no formula at all. Both must
# be importable by the python3 on PATH, so install them against that
# interpreter with uv (from the Brewfile above).
#
# Refuse the Xcode command-line-tools interpreter: it is root-owned, so the
# install either fails on permissions or pollutes a tree that a CLT update
# wipes -- and either way the tests keep skipping, which is the failure this
# step exists to prevent.
#----------------------------------------------------------
if util::confirm "Install python packages (pygments, pyyaml)?"; then
  # `mise install` does not change PATH in this process, and mise activates from
  # .zshrc, which a non-interactive setup never reads -- so ask mise directly and
  # keep command -v only as the fallback for a machine without mise.
  PY="$(mise which python3 2>/dev/null || command -v python3)"
  if ! util::has uv; then
    util::warning "uv not found; skipping python packages (install the Brewfile first)."
  elif [[ -z "${PY}" ]]; then
    util::warning "no python3 on PATH; skipping python packages."
  elif [[ "${PY}" == /usr/bin/python3 || "${PY}" == /Library/Developer/* || "${PY}" == /Applications/Xcode*.app/* ]]; then
    util::warning "python3 is the Xcode CLT interpreter (${PY}); mise install did not provide one."
  elif [[ "${PY}" == /opt/homebrew/* || "${PY}" == /usr/local/Cellar/* ]]; then
    # Homebrew marks its interpreters externally managed, so uv refuses them
    # outright rather than half-installing.
    util::warning "python3 is Homebrew's (${PY}), which is externally managed; mise install did not provide one."
  else
    util::info "Installing pygments and pyyaml into ${PY}"
    uv pip install --quiet --python "${PY}" pygments pyyaml \
      || util::warning "python packages failed; highlight-code and server tests will skip."
  fi
fi

#----------------------------------------------------------
# VSCode Extensions
#----------------------------------------------------------
if util::confirm "Install VSCode extensions?"; then
  source "${REPO_DIR}/.vscode/install.zsh"
fi

#----------------------------------------------------------
# Cursor Extensions
#----------------------------------------------------------
if util::confirm "Install Cursor extensions?"; then
  source "${REPO_DIR}/.cursor/install.zsh"
fi

#----------------------------------------------------------
# macOS settings
#
# Skipped in CI: the runner does not need the defaults and some need sudo.
#----------------------------------------------------------
if ! util::is_ci && util::confirm "Apply macOS settings?"; then
  source "${REPO_DIR}/macos/install.zsh"
fi

#----------------------------------------------------------
# TCP keepalive tuning (corporate firewall NAT idle timeout workaround)
#
# Details: docs/superpowers/specs/2026-07-09-tcp-keepalive-firewall-timeout-design.md
# LaunchDaemon, not LaunchAgent, since sysctl -w needs root. Copied (not
# symlinked) with root:wheel 644, since launchd checks plist ownership.
#----------------------------------------------------------
if util::confirm "Apply TCP keepalive tuning (企業ファイアウォールのタイムアウト対策)?"; then
  PLIST_NAME="local.tcp-keepalive-tuning.plist"
  SRC_PLIST="${REPO_DIR}/macos/${PLIST_NAME}"
  DEST_PLIST="/Library/LaunchDaemons/${PLIST_NAME}"
  if [[ -f "${SRC_PLIST}" ]]; then
    sudo cp "${SRC_PLIST}" "${DEST_PLIST}"
    sudo chown root:wheel "${DEST_PLIST}"
    sudo chmod 644 "${DEST_PLIST}"
    sudo launchctl bootstrap system "${DEST_PLIST}" 2>/dev/null \
      || sudo launchctl load -w "${DEST_PLIST}"
    sudo sysctl -w net.inet.tcp.keepidle=5000 net.inet.tcp.keepintvl=3000 \
      net.inet.tcp.keepcnt=8 net.inet.tcp.always_keepalive=1
    util::info "TCP keepalive tuning applied and persisted via LaunchDaemon."
  else
    util::info "Skip: macos/${PLIST_NAME} not found."
  fi
fi

#----------------------------------------------------------
# Handy voice post-processing (ollama model + LOCAL default)
#
# Defaults to LOCAL (offline ollama) so a fresh Mac works with no API key.
# Cloud (Cerebras) is opt-in: it neither retains nor trains on data
#   https://support.cerebras.net/articles/1811589793-does-cerebras-retain-my-data
#   https://www.cerebras.ai/terms-of-service
#----------------------------------------------------------
if util::confirm "Set up Handy voice post-processing (ollama model + settings)?"; then
  if util::has ollama; then
    open -a Ollama 2>/dev/null || true   # ollama-app starts the localhost:11434 server
    ollama pull qwen3:4b-instruct-2507-q4_K_M || util::warning "ollama pull failed; run it manually later"
  else
    util::warning "ollama CLI not found. Launch Ollama once, then: ollama pull qwen3:4b-instruct-2507-q4_K_M"
  fi

  if [[ -d "/Applications/Handy.app" ]]; then
    HANDY_SETTINGS="$HOME/Library/Application Support/com.pais.handy/settings_store.json"
    if [[ ! -f "$HANDY_SETTINGS" ]]; then
      open -a Handy                       # first launch generates settings_store.json
      for i in {1..50}; do [[ -f "$HANDY_SETTINGS" ]] && break; sleep 0.2; done
    fi
    if [[ -f "$HANDY_SETTINGS" ]]; then
      "${REPO_DIR}/bin/voice-switch" local && util::info "Voice post-processing set to LOCAL (offline ollama)."
    else
      util::warning "Handy settings not generated; launch Handy once, then run 'voice-switch local'."
    fi
  else
    util::warning "Handy.app not installed; install via Brewfile, launch once, then run 'voice-switch local'."
  fi

  util::warning "Manual step (cannot be scripted): grant Handy these permissions or recording/paste fails:"
  util::warning "  - Microphone (System Settings > Privacy & Security > Microphone) -- to record"
  util::warning "  - Accessibility (System Settings > Privacy & Security > Accessibility) -- to paste (CtrlV)"

  util::info "To enable Cerebras cloud (faster + higher quality; no data retention/training):"
  util::info "  1) security add-generic-password -s handy-cerebras-api-key -a \"\$USER\" -w \"<KEY>\""
  util::info "  2) voice-switch cloud"
fi

#----------------------------------------------------------
# slackcli (not available via Homebrew)
#----------------------------------------------------------
if util::confirm "Install slackcli?"; then
  local arch=$(uname -m)
  local suffix="macos"
  [[ "$arch" = "arm64" ]] && suffix="macos-arm64"
  mkdir -p "$HOME/.local/bin"
  local dest="$HOME/.local/bin/slackcli"
  if command -v slackcli &>/dev/null; then
    util::info "slackcli already installed: $(slackcli --version)"
  else
    local tmp
    tmp="$(mktemp -t slackcli)" || return 1
    curl -fSL "https://github.com/shaharia-lab/slackcli/releases/latest/download/slackcli-${suffix}" -o "${tmp}"
    chmod +x "${tmp}"
    mv "${tmp}" "$dest"
    util::info "slackcli installed to $dest"
  fi
fi

#----------------------------------------------------------
# User LaunchAgents (voice warm-up + Secure Input watch)
#
# Plists use a __DOTFILES__ placeholder substituted at install time, so the
# repo can live at any path. Skipped in CI: the runner has no Handy/Ghostty,
# so the agents would only respawn and fail on a timer.
#----------------------------------------------------------
if ! util::is_ci && util::confirm "Install user LaunchAgents (handy-warm, secure-input-watch, voice-quota-watch, discord-relay-flush)?"; then
  mkdir -p "$HOME/Library/LaunchAgents"
  for name in com.snakashima.handy-warm com.snakashima.secure-input-watch com.snakashima.voice-quota-watch com.snakashima.discord-relay-flush; do
    src="${REPO_DIR}/macos/${name}.plist"
    dest="$HOME/Library/LaunchAgents/${name}.plist"
    if [[ ! -f "${src}" ]]; then
      util::warning "Skip ${name}: ${src} not found."
      continue
    fi
    sed "s|__DOTFILES__|${REPO_DIR}|g" "${src}" > "${dest}"
    launchctl bootout "gui/$(id -u)/${name}" 2>/dev/null || true
    if launchctl bootstrap "gui/$(id -u)" "${dest}"; then
      util::info "LaunchAgent installed: ${name}"
    else
      util::warning "LaunchAgent bootstrap failed: ${name} (plist written to ${dest})"
    fi
  done
fi

#----------------------------------------------------------
# Discord relay allowlist
#
# Deny by default: the relay posts file paths, commands and tool arguments, so a
# repository absent from this file produces nothing at all. The file lives
# outside the repo on purpose -- adding a work remote to a tracked file would
# publish its name in a public repo.
#----------------------------------------------------------
DISCORD_ALLOWLIST="$HOME/.config/discord-relay/allowlist"
if [[ ! -f "$DISCORD_ALLOWLIST" ]]; then
  mkdir -p "${DISCORD_ALLOWLIST:h}"
  print 'https://github.com/cmb-sy/dotfiles.git' > "$DISCORD_ALLOWLIST"
  util::info "Created ${DISCORD_ALLOWLIST} (this repo only). One remote URL per line to relay more."
fi
util::info "To enable the Discord relay, create a Forum channel and register its webhook:"
util::info "  security add-generic-password -s claude-discord-webhook -a \"\$USER\" -w \"<WEBHOOK URL>\""

util::info "Cleanup..."
brew cleanup 2>/dev/null || true
util::info "Done!"
