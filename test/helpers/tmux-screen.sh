#!/bin/bash
# Capture what a program actually renders, by running it under tmux.
#
# Reading a pty's byte stream does not answer "what is on screen": Neovim sends
# differential updates, so a cell that did not change is never re-sent and a
# time-sliced scan of the stream misses it. tmux keeps the screen model, and
# capture-pane returns the rendered result.
#
#   tmux-screen.sh start <session> <command...>   launch, detached
#   tmux-screen.sh grab  <session>                print the current screen
#   tmux-screen.sh keys  <session> <keys>         send keys
#   tmux-screen.sh stop  <session>                kill it
#
# Each session gets its own XDG_STATE_HOME, so a killed editor cannot leave a
# swap file that blocks the real one later.

set -euo pipefail

state_dir_for() {
    echo "${TMPDIR:-/private/tmp}/tmux-screen-$1"
}

case "${1:-}" in
    start)
        session=$2
        shift 2
        state=$(state_dir_for "$session")
        rm -rf "$state"
        mkdir -p "$state"
        tmux kill-session -t "$session" 2>/dev/null || true
        # A fixed size keeps assertions about layout reproducible.
        tmux new-session -d -s "$session" -x 100 -y 24 \
            "XDG_STATE_HOME='$state' $*"
        ;;
    grab)
        tmux capture-pane -p -t "$2"
        ;;
    keys)
        tmux send-keys -t "$2" "$3"
        ;;
    stop)
        session=$2
        tmux kill-session -t "$session" 2>/dev/null || true
        rm -rf "$(state_dir_for "$session")"
        ;;
    *)
        echo "usage: tmux-screen.sh {start|grab|keys|stop} <session> [args]" >&2
        exit 64
        ;;
esac
