#!/usr/bin/env python3
"""Run the real Neovim config in a pty and report what the screen showed.

`nvim --headless` does not exercise the parts that only exist on a screen: the
ruler, the statusline, and anything a timer paints. It also cannot see a runtime
error raised after startup -- which is how a libuv callback calling vim.fn.mode()
shipped, passing every headless check while erroring on the first keystroke.

    nvim-pty.py <file> [--insert-dwell 2.5] [--keys i,esc]

Prints JSON: {"errors": [...], "text": "screen output with escapes stripped"}

The harness answers the terminal queries Neovim makes on startup (background
colour, DSR, kitty keyboard flags). Without the replies Neovim reports E1568 and
the message sits on the line the ruler would occupy, so the very thing under test
becomes unreadable.
"""

import argparse
import json
import os
import pty
import re
import select
import shutil
import signal
import sys
import tempfile
import time

# Written by a real terminal in response to Neovim's startup queries.
REPLIES = [
    (b"\x1b]11;?", b"\x1b]11;rgb:1616/1d1d/2f2f\x1b\\"),   # background colour
    (b"\x1b]10;?", b"\x1b]10;rgb:dbdb/e2e2/f0f0\x1b\\"),   # foreground colour
    (b"\x1b[5n", b"\x1b[0n"),                              # device status
    (b"\x1b[6n", b"\x1b[1;1R"),                            # cursor position
    (b"\x1b[?u", b"\x1b[?1u"),                             # kitty keyboard flags
]

KEYS = {
    "esc": b"\x1b",
    "ctrl-l": b"\x0c",          # force a repaint, clearing any pending message
    "cr": b"\r",
}

ESCAPES = re.compile(
    r"\x1b\[[0-9;?]*[A-Za-z]"        # CSI
    r"|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)"  # OSC
    r"|\x1b[()][A-B0-9]"             # charset selection
    r"|\x1b[=>]"                     # keypad mode
)

ERROR_PATTERN = re.compile(r"E\d{3,4}:|Lua callback|stack traceback|Error executing")


def reap(pid: int, fd: int) -> None:
    """Wait briefly, then kill. A blocking waitpid hangs forever when Neovim
    refuses to quit -- a modified buffer, a prompt -- and a hung test is worse
    than a failing one, because nothing says which test it was."""
    deadline = time.time() + 3
    while time.time() < deadline:
        try:
            done, _ = os.waitpid(pid, os.WNOHANG)
        except ChildProcessError:
            return
        if done:
            return
        time.sleep(0.1)
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.kill(pid, sig)
        except ProcessLookupError:
            return
        time.sleep(0.3)
        try:
            done, _ = os.waitpid(pid, os.WNOHANG)
            if done:
                return
        except ChildProcessError:
            return


def run(target: str, keys: list[str], dwell: float) -> dict:
    # An isolated state directory, so a killed run cannot leave a swap file
    # behind that then blocks the real editor with E325 the next time the same
    # file is opened. Undo history and shada are separated for the same reason.
    state = tempfile.mkdtemp(prefix="nvim-pty-state-")

    pid, fd = pty.fork()
    if pid == 0:
        os.environ["TERM"] = "xterm-256color"
        os.environ["LINES"] = "24"
        os.environ["COLUMNS"] = "100"
        os.environ["XDG_STATE_HOME"] = state
        os.execvp("nvim", ["nvim", target])

    buf = bytearray()

    def drain(seconds: float) -> None:
        end = time.time() + seconds
        while time.time() < end:
            ready, _, _ = select.select([fd], [], [], 0.1)
            if not ready:
                continue
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                return
            if not chunk:
                return
            buf.extend(chunk)
            for query, answer in REPLIES:
                if query in chunk:
                    try:
                        os.write(fd, answer)
                    except OSError:
                        return

    drain(3.0)                       # startup, plugins, first paint
    for key in keys:
        os.write(fd, KEYS.get(key, key.encode()))
        # A dwell after entering insert lets repeating timers tick several times.
        drain(dwell if key == "i" else 0.8)
    os.write(fd, b"\x0c")            # repaint before the final read
    drain(0.8)
    os.write(fd, b":qa!\r")
    drain(1.5)
    reap(pid, fd)

    shutil.rmtree(state, ignore_errors=True)

    text = ESCAPES.sub("", buf.decode("utf-8", "replace"))
    return {"errors": sorted(set(ERROR_PATTERN.findall(text))), "text": text}


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("file")
    ap.add_argument("--keys", default="i,esc",
                    help="comma-separated keys to send (esc, ctrl-l, cr, or literal text)")
    ap.add_argument("--insert-dwell", type=float, default=2.5,
                    help="seconds to stay in insert mode, so repeating timers fire")
    args = ap.parse_args()

    if not os.path.exists(args.file):
        sys.exit(f"nvim-pty: no such file: {args.file}")
    print(json.dumps(run(args.file, args.keys.split(","), args.insert_dwell)))


if __name__ == "__main__":
    main()
