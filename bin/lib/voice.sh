# bin/lib/voice.sh — shared definitions for the voice-input scripts.
#
# Sourced, never executed. Callers are a mix of bash and zsh, so keep this
# POSIX: no [[ ]], no arrays, no bashisms.
#
#   . "$(cd "$(dirname "$0")" && pwd)/lib/voice.sh"
#
# Handy's own paths and process name live here so a change on Handy's side is
# one edit, not a hunt through bin/.

# Handy writes its settings here; apply-settings.py rewrites this file.
HANDY_SETTINGS="$HOME/Library/Application Support/com.pais.handy/settings_store.json"

# Typeless is Electron-based, so its binary name can shift between releases.
# Detect it by bundle path instead of by name.
TYPELESS_APP="/Applications/Typeless.app"
TYPELESS_BIN_DIR="$TYPELESS_APP/Contents/MacOS/"

KARABINER_CLI="/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli"

# PATH for the scripts launchd and Karabiner start: those run with a minimal
# environment that has no homebrew.
VOICE_LAUNCHD_PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

# pgrep through PATH so tests can stub it, with the absolute path as the
# fallback for the minimal launchd environment.
voice_pgrep() {
  if command -v pgrep >/dev/null 2>&1; then
    pgrep "$@"
  else
    /usr/bin/pgrep "$@"
  fi
}

# The binary is lowercase `handy` inside Handy.app; pgrep -x is case-sensitive
# and matching the wrong case silently reports "not running".
handy_running() {
  voice_pgrep -x handy >/dev/null 2>&1
}

typeless_running() {
  voice_pgrep -f "$TYPELESS_BIN_DIR" >/dev/null 2>&1
}

# notify <title> <message> — macOS banner. Callers pass fixed short strings:
# the message is interpolated into an AppleScript string literal, so no
# variable-length body here. Best-effort; a failed banner is never fatal.
notify() {
  "${OSASCRIPT_BIN:-/usr/bin/osascript}" \
    -e "display notification \"$2\" with title \"$1\"" >/dev/null 2>&1 || true
}

# Prepend the launchd PATH, keeping whatever the caller inherited.
ensure_launchd_path() {
  PATH="$VOICE_LAUNCHD_PATH${PATH:+:$PATH}"
  export PATH
}
