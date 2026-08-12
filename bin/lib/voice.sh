# bin/lib/voice.sh — shared definitions for the voice scripts, in and out.
#
# Sourced, never executed. Callers are a mix of bash and zsh, so keep this
# POSIX: no [[ ]], no arrays, no bashisms.
#
#   . "${BASH_SOURCE[0]%/*}/lib/voice.sh"   # zsh: "${0:A:h}/lib/voice.sh"
#
# The lines each caller uses to find this file cannot live here -- they run
# before it is loaded. Relative is enough for all of them: launchd and Karabiner
# invoke absolute paths, and none of the scripts cd. bin/secure-input-watch keeps
# an absolute $HERE only because it reuses it to build other paths, where a bare
# "." would read as a lost cwd rather than as "next to the script".
#
# Handy's own paths and process name live here so a change on Handy's side is
# one edit, not a hunt through bin/.

# Handy writes its settings here; apply-settings.py rewrites this file.
# An empty HOME would silently make this /Library/..., which reads back as
# "Handy has not written settings yet", so refuse it instead.
HANDY_SETTINGS="${HOME:?voice.sh: HOME is not set}/Library/Application Support/com.pais.handy/settings_store.json"

# Typeless is Electron-based, so its binary name can shift between releases.
# Detect it by bundle path instead of by name.
TYPELESS_APP="/Applications/Typeless.app"
TYPELESS_BIN_DIR="$TYPELESS_APP/Contents/MacOS/"

# Typeless logs every dictation with its duration here. It records no quota,
# limit or reset date -- the server decides and shows an upgrade ad -- so the
# only way to know the weekly allowance is to add up this log.
# Overridable so tests can point at a stub database, as bin/secure-input-watch
# does for its binaries.
TYPELESS_DB="${TYPELESS_DB:-${HOME:?voice.sh: HOME is not set}/Library/Application Support/Typeless/typeless.db}"

KARABINER_CLI="/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli"

# PATH for the scripts launchd and Karabiner start: those run with a minimal
# environment that has no homebrew.
VOICE_LAUNCHD_PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

# Absolute path: Karabiner and launchd start these scripts with a minimal
# environment. Overridable so tests can stub it, as bin/secure-input-watch does
# for its own binaries.
PGREP_BIN="${PGREP_BIN:-/usr/bin/pgrep}"

# The binary is lowercase `handy` inside Handy.app; pgrep -x is case-sensitive
# and matching the wrong case silently reports "not running".
handy_running() {
  "$PGREP_BIN" -x handy >/dev/null 2>&1
}

typeless_running() {
  "$PGREP_BIN" -f "$TYPELESS_BIN_DIR" >/dev/null 2>&1
}

# notify <title> <message> — macOS banner. Callers pass fixed short strings:
# the message is interpolated into an AppleScript string literal, so no
# variable-length body here. Best-effort; a failed banner is never fatal.
notify() {
  "${OSASCRIPT_BIN:-/usr/bin/osascript}" \
    -e "display notification \"$2\" with title \"$1\"" >/dev/null 2>&1 || true
}

# Replace PATH rather than prepend. Karabiner and launchd hand these scripts a
# minimal environment, and an inherited PATH can carry the working directory --
# every binary the voice scripts call lives in VOICE_LAUNCHD_PATH already.
ensure_launchd_path() {
  PATH="$VOICE_LAUNCHD_PATH"
  export PATH
}

# --- speech output ---------------------------------------------------------
# Everything below answers "how do we say it": text cleanup for a synthesizer
# and the two TTS backends. What to say stays with the caller (bin/voice-out).

TTS_VOICE="${CLAUDE_TTS_VOICE:-Kyoko}"
TTS_RATE="${CLAUDE_TTS_RATE:-180}"
# voicevox when its engine answers on localhost, say otherwise.
TTS_BACKEND="${CLAUDE_TTS_BACKEND:-voicevox}"
VOICEVOX_URL="${CLAUDE_TTS_VOICEVOX_URL:-http://localhost:50021}"
VOICEVOX_SPEAKER="${CLAUDE_TTS_VOICEVOX_SPEAKER:-8}"
VOICEVOX_SPEED="${CLAUDE_TTS_VOICEVOX_SPEED:-1.0}"

voice_log() {
  [ -n "$CLAUDE_TTS_DEBUG" ] && \
    printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >> /tmp/voice-out.log
  return 0
}

# sanitize_text — stdin markdown, stdout plain prose a synthesizer can read.
sanitize_text() {
  /usr/bin/awk '
      BEGIN { inc = 0 }
      /^```/ {
        if (inc == 0) { inc = 1 }
        else          { inc = 0; print "コードブロック省略。" }
        next
      }
      inc == 0 { print }
    ' \
    | /usr/bin/awk '
        BEGIN { in_tbl = 0 }
        /^\|.*\|$/ {
          if (in_tbl == 0) { print "表省略。"; in_tbl = 1 }
          next
        }
        { in_tbl = 0; print }
      ' \
    | /usr/bin/sed -E 's|https?://[^[:space:]]+|リンク。|g' \
    | /usr/bin/sed -E 's/^#+[[:space:]]*//' \
    | /usr/bin/sed -E 's/^[[:space:]]*[-*][[:space:]]+//' \
    | /usr/bin/sed -E 's/\*\*([^*]+)\*\*/\1/g' \
    | /usr/bin/sed -E 's/`([^`]+)`/\1/g' \
    | /usr/bin/sed -E 's/^>[[:space:]]*//' \
    | /usr/bin/awk '
        BEGIN { blank = 0 }
        /^$/ { blank++; if (blank <= 1) print; next }
        { blank = 0; print }
      '
}

# speak_voicevox <text> — synthesize through the VOICEVOX engine, play with
# afplay. Returns non-zero on any failure (engine down, API error, empty wav)
# so the caller can fall back to say.
speak_voicevox() {
  local text="$1"
  local wav
  # Reachability first, giving up after a second.
  /usr/bin/curl -s --max-time 1 "$VOICEVOX_URL/version" >/dev/null 2>&1 \
    || { voice_log "voicevox engine not reachable at $VOICEVOX_URL"; return 1; }
  local query
  query=$(/usr/bin/curl -s --max-time 10 -X POST \
    "$VOICEVOX_URL/audio_query?speaker=$VOICEVOX_SPEAKER" \
    --get --data-urlencode "text=$text" 2>/dev/null)
  [ -z "$query" ] && { voice_log "voicevox audio_query failed"; return 1; }
  query=$(printf '%s' "$query" \
    | /opt/homebrew/bin/jq --arg s "$VOICEVOX_SPEED" '.speedScale = ($s | tonumber)' 2>/dev/null)
  [ -z "$query" ] && { voice_log "voicevox query patch failed"; return 1; }
  wav=$(mktemp -t voicevox.XXXXXX) || return 1
  /usr/bin/curl -s --max-time 30 -X POST \
    "$VOICEVOX_URL/synthesis?speaker=$VOICEVOX_SPEAKER" \
    -H "Content-Type: application/json" \
    -d "$query" \
    -o "$wav" 2>/dev/null
  if [ ! -s "$wav" ]; then
    voice_log "voicevox synthesis empty"
    rm -f "$wav"
    return 1
  fi
  voice_log "voicevox speak (speaker=$VOICEVOX_SPEAKER, speed=$VOICEVOX_SPEED, wav=${wav}, ${#text} chars)"
  # Play in the background and take the wav with it.
  ( /usr/bin/afplay "$wav"; rm -f "$wav" ) &
  return 0
}

# speak_say <text> — macOS say, the always-available backend.
speak_say() {
  printf '%s' "$1" | /usr/bin/say -v "$TTS_VOICE" -r "$TTS_RATE" &
}

# speak <text> — preferred backend, falling back to say.
speak() {
  if [ "$TTS_BACKEND" = "voicevox" ]; then
    speak_voicevox "$1" && return 0
    voice_log "falling back to say"
  fi
  speak_say "$1"
}

# Both backends play through their own process, so the toggle asks and kills
# by process name rather than tracking a pid.
speaking_active() {
  "$PGREP_BIN" -x say >/dev/null 2>&1 || "$PGREP_BIN" -x afplay >/dev/null 2>&1
}

kill_speaking() {
  /usr/bin/pkill -x say 2>/dev/null
  /usr/bin/pkill -x afplay 2>/dev/null
}
