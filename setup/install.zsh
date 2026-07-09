#!/bin/zsh

SCRIPT_DIR="${0:A:h}"
REPO_DIR="${SCRIPT_DIR:h}"
source "${SCRIPT_DIR}/util.zsh"

util::info "Starting dotfiles installation..."

#----------------------------------------------------------
# Homebrew (Brewfile)
#----------------------------------------------------------
util::confirm "Install packages from Brewfile?"
if [[ $? = 0 ]]; then
  export HOMEBREW_NO_AUTO_UPDATE=1
  export HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1
  brew bundle --file="${REPO_DIR}/Brewfile" --quiet
fi

#----------------------------------------------------------
# VSCode Extensions
#----------------------------------------------------------
util::confirm "Install VSCode extensions?"
if [[ $? = 0 ]]; then
  source "${REPO_DIR}/.vscode/install.zsh"
fi

#----------------------------------------------------------
# Cursor Extensions
#----------------------------------------------------------
util::confirm "Install Cursor extensions?"
if [[ $? = 0 ]]; then
  source "${REPO_DIR}/.cursor/install.zsh"
fi

#----------------------------------------------------------
# macOS settings (skip password prompt when FORCE=1)
#----------------------------------------------------------
if [[ ${FORCE} != 1 ]] && util::confirm "Apply macOS settings?"; then
  source "${REPO_DIR}/macos/install.zsh"
fi

#----------------------------------------------------------
# TCP keepalive tuning (企業ファイアウォールのNATアイドルタイムアウト対策)
#
# 詳細: docs/superpowers/specs/2026-07-09-tcp-keepalive-firewall-timeout-design.md
# root権限が必要なため LaunchAgent ではなく LaunchDaemon。symlinkではなくコピー
# して root:wheel 644 に設定する（launchd はplistの所有権を検証するため）。
#----------------------------------------------------------
util::confirm "Apply TCP keepalive tuning (企業ファイアウォールのタイムアウト対策)?"
if [[ $? = 0 ]]; then
  PLIST_NAME="com.snakashima.tcp-keepalive-tuning.plist"
  SRC_PLIST="${REPO_DIR}/macos/${PLIST_NAME}"
  DEST_PLIST="/Library/LaunchDaemons/${PLIST_NAME}"
  if [[ -f "${SRC_PLIST}" ]]; then
    sudo cp "${SRC_PLIST}" "${DEST_PLIST}"
    sudo chown root:wheel "${DEST_PLIST}"
    sudo chmod 644 "${DEST_PLIST}"
    sudo launchctl bootstrap system "${DEST_PLIST}" 2>/dev/null \
      || sudo launchctl load -w "${DEST_PLIST}"
    sudo sysctl -w net.inet.tcp.keepidle=30000 net.inet.tcp.keepintvl=15000 \
      net.inet.tcp.keepcnt=8 net.inet.tcp.always_keepalive=1
    util::info "TCP keepalive tuning applied and persisted via LaunchDaemon."
  else
    util::info "Skip: macos/${PLIST_NAME} not found."
  fi
fi

#----------------------------------------------------------
# WezTerm
#----------------------------------------------------------
util::confirm "Set up WezTerm config?"
if [[ $? = 0 ]]; then
  mkdir -p "$HOME/.config"
  if [[ -d "${REPO_DIR}/terminal/wezterm" ]]; then
    ln -sfn "${REPO_DIR}/terminal/wezterm" "$HOME/.config/wezterm"
    util::info "WezTerm config linked to ~/.config/wezterm."
  else
    util::info "Skip: terminal/wezterm not found."
  fi
fi

#----------------------------------------------------------
# Karabiner-Elements (Caps Lock 二度押し → 音声入力)
#----------------------------------------------------------
util::confirm "Set up Karabiner-Elements config?"
if [[ $? = 0 ]]; then
  mkdir -p "$HOME/.config"
  if [[ -d "${REPO_DIR}/karabiner" ]]; then
    # Karabiner は初回起動で実ディレクトリを生成する。symlink がその中に作られるのを防ぐため退避する
    if [[ -e "$HOME/.config/karabiner" && ! -L "$HOME/.config/karabiner" ]]; then
      mv "$HOME/.config/karabiner" "$HOME/.config/karabiner.bak.$(date +%s)"
    fi
    ln -sfn "${REPO_DIR}/karabiner" "$HOME/.config/karabiner"
    util::info "Karabiner config linked to ~/.config/karabiner."
    util::warning "Manual step (cannot be scripted): launch Karabiner-Elements once and grant:"
    util::warning "  - the driver/system extension approval it prompts for on first launch"
    util::warning "  - Input Monitoring (System Settings > Privacy & Security > Input Monitoring)"
    util::warning "  Without these, Caps Lock -> Handy voice input silently does nothing."
  else
    util::info "Skip: karabiner not found."
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
util::confirm "Set up Handy voice post-processing (ollama model + settings)?"
if [[ $? = 0 ]]; then
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
# tmux
#----------------------------------------------------------
util::confirm "Set up tmux config?"
if [[ $? = 0 ]]; then
  if [[ -f "${REPO_DIR}/tmux/tmux.conf" && -f "${REPO_DIR}/tmux/sessionizer.sh" ]]; then
    mkdir -p "$HOME/.config/tmux"
    ln -sf "${REPO_DIR}/tmux/tmux.conf" "$HOME/.config/tmux/tmux.conf"
    mkdir -p "$HOME/.local/bin"
    ln -sf "${REPO_DIR}/tmux/sessionizer.sh" "$HOME/.local/bin/tmux-sessionizer"
    chmod +x "${REPO_DIR}/tmux/sessionizer.sh"
    util::info "tmux config and sessionizer linked."
  else
    util::info "Skip: tmux/tmux.conf or tmux/sessionizer.sh not found."
  fi
fi

#----------------------------------------------------------
# herdr (agent multiplexer)
#
# ~/.config/herdr は config.toml 以外にサーバーのログ/ソケット/session.json
# を書き込み続けるため、terminal/* の一括ディレクトリ symlink 対象にはせず、
# tmux と同様に config.toml だけをファイル単位で symlink する。
#----------------------------------------------------------
util::confirm "Set up herdr config?"
if [[ $? = 0 ]]; then
  if [[ -f "${REPO_DIR}/terminal/herdr/config.toml" ]]; then
    mkdir -p "$HOME/.config/herdr"
    ln -sf "${REPO_DIR}/terminal/herdr/config.toml" "$HOME/.config/herdr/config.toml"
    util::info "herdr config linked to ~/.config/herdr/config.toml."
  else
    util::info "Skip: terminal/herdr/config.toml not found."
  fi
fi

#----------------------------------------------------------
# Cursor (skills shared with Claude)
#----------------------------------------------------------
util::confirm "Set up Cursor config?"
if [[ $? = 0 ]]; then
  mkdir -p "$HOME/.cursor"
  if [[ -d "${REPO_DIR}/claude/skills" ]]; then
    ln -sfn "${REPO_DIR}/claude/skills" "$HOME/.cursor/skills"
    util::info "Cursor skills linked (shared with Claude)."
  fi
fi

#----------------------------------------------------------
# slackcli (not available via Homebrew)
#----------------------------------------------------------
util::confirm "Install slackcli?"
if [[ $? = 0 ]]; then
  local arch=$(uname -m)
  local suffix="macos"
  [[ "$arch" = "arm64" ]] && suffix="macos-arm64"
  mkdir -p "$HOME/.local/bin"
  local dest="$HOME/.local/bin/slackcli"
  if command -v slackcli &>/dev/null; then
    util::info "slackcli already installed: $(slackcli --version)"
  else
    curl -fSL "https://github.com/shaharia-lab/slackcli/releases/latest/download/slackcli-${suffix}" -o /tmp/slackcli
    chmod +x /tmp/slackcli
    mv /tmp/slackcli "$dest"
    util::info "slackcli installed to $dest"
  fi
fi

util::info "Cleanup..."
brew cleanup 2>/dev/null || true
util::info "Done!"
