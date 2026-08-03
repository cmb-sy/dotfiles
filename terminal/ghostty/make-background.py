#!/usr/bin/env python3
"""Generate the faint circuit-trace background for Ghostty.

Run from anywhere:  python3 terminal/ghostty/make-background.py

Writes background.png beside this script. The output is committed, so this
only needs running to change the look.

Design constraints:
  - Text sits on top of this, and readability comes first. Traces are drawn at
    low alpha on a transparent canvas, so the terminal's own background shows
    through and the pattern only lifts it slightly.
  - `background` in the Ghostty config is an explicit dark purple that wins
    over the light/dark theme, so the pattern can assume a dark ground and use
    a light tint.
  - Seeded, so regenerating gives the same image rather than a random new one
    in every diff.
"""

import random
from PIL import Image, ImageDraw

WIDTH, HEIGHT = 2560, 1440
GRID = 80                      # spacing between possible trace lanes
TRACE = (150, 132, 214, 26)    # periwinkle, low alpha: lifts the ground a little
PAD = (168, 150, 226, 34)      # pads slightly brighter so junctions read
SEED = 20260803

random.seed(SEED)
img = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

cols, rows = WIDTH // GRID, HEIGHT // GRID


def walk(cx, cy, steps):
    """One trace: right angles with the occasional 45-degree cut, like a PCB."""
    points = [(cx * GRID, cy * GRID)]
    horizontal = random.random() < 0.5
    for _ in range(steps):
        run = random.randint(1, 4)
        if horizontal:
            cx += run if random.random() < 0.5 else -run
        else:
            cy += run if random.random() < 0.5 else -run
        cx, cy = max(0, min(cols, cx)), max(0, min(rows, cy))
        points.append((cx * GRID, cy * GRID))
        horizontal = not horizontal
    return points


for _ in range(90):
    pts = walk(random.randint(0, cols), random.randint(0, rows), random.randint(3, 9))
    draw.line(pts, fill=TRACE, width=2, joint="curve")
    # Pads at both ends, the way a trace terminates at a component.
    for x, y in (pts[0], pts[-1]):
        draw.ellipse((x - 5, y - 5, x + 5, y + 5), outline=PAD, width=2)

# A sparse dot grid underneath, echoing a perfboard, at half the trace alpha.
faint = (TRACE[0], TRACE[1], TRACE[2], 12)
for gx in range(0, WIDTH + 1, GRID * 2):
    for gy in range(0, HEIGHT + 1, GRID * 2):
        draw.point((gx, gy), fill=faint)

out = __file__.rsplit("/", 1)[0] + "/background.png"
img.save(out, optimize=True)
print(f"wrote {out} ({WIDTH}x{HEIGHT})")
