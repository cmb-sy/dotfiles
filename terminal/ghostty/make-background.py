#!/usr/bin/env python3
"""Generate the background image for Ghostty.

Run from anywhere:  python3 terminal/ghostty/make-background.py

Writes background.png beside this script. The output is committed, so this
only needs running to change the look.

Design constraints:
  - Text sits on top of this, and readability comes first. Two rules follow
    from that. Everything is drawn at low alpha on a transparent canvas, so the
    terminal's own background shows through. And the large shapes are kept
    deliberately soft and low-frequency: broad gradients interfere with small
    text far less than fine detail at the same contrast does, because they do
    not compete at the scale the glyphs occupy.
  - A vignette darkens the edges, where prompts and status lines tend to sit.
  - `background` in the Ghostty config is an explicit dark purple that wins
    over the light/dark theme, so this can assume a dark ground and lift it.
    Hues are taken from the config's own ANSI overrides so the two agree.
  - Seeded, so regenerating gives the same image rather than a random new one
    in every diff.

Tune the look with GLOW_ALPHA (the soft shapes) and TRACE_ALPHA (the fine
lines); Ghostty's background-image-opacity scales the whole thing on top.
"""

import math
import random

from PIL import Image, ImageDraw, ImageFilter

WIDTH, HEIGHT = 2560, 1440
SEED = 20260804

# Hues lifted from the ANSI overrides in terminal/ghostty/config.
PINK = (255, 92, 138)
CYAN = (92, 200, 255)
VIOLET = (193, 140, 255)
MINT = (92, 255, 180)

GLOW_ALPHA = 96   # peak alpha of the soft shapes, before blurring
TRACE_ALPHA = 26  # the fine circuit lines
GRID = 80         # spacing of the trace lanes

random.seed(SEED)


def soft_glows() -> Image.Image:
    """Large low-frequency colour fields, blurred until no edge is visible."""
    layer = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    blobs = [
        (0.74, 0.20, 0.46, PINK),
        (0.18, 0.72, 0.52, CYAN),
        (0.52, 0.46, 0.60, VIOLET),
        (0.90, 0.82, 0.34, MINT),
    ]
    for fx, fy, fr, colour in blobs:
        cx, cy = fx * WIDTH, fy * HEIGHT
        r = fr * HEIGHT
        # Concentric rings fading outward: cheaper than a real radial gradient
        # and indistinguishable once blurred.
        steps = 26
        for i in range(steps, 0, -1):
            t = i / steps
            rr = r * t
            a = int(GLOW_ALPHA * (1 - t) ** 2)
            if a <= 0:
                continue
            draw.ellipse((cx - rr, cy - rr, cx + rr, cy + rr), fill=colour + (a,))
    return layer.filter(ImageFilter.GaussianBlur(140))


def circuit_traces() -> Image.Image:
    """Fine right-angle traces with pads, as a texture over the glows."""
    layer = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    ink = (150, 132, 214, TRACE_ALPHA)
    pad = (168, 150, 226, TRACE_ALPHA + 8)
    cols, rows = WIDTH // GRID, HEIGHT // GRID

    for _ in range(70):
        cx, cy = random.randint(0, cols), random.randint(0, rows)
        points = [(cx * GRID, cy * GRID)]
        horizontal = random.random() < 0.5
        for _ in range(random.randint(3, 9)):
            run = random.randint(1, 4)
            if horizontal:
                cx += run if random.random() < 0.5 else -run
            else:
                cy += run if random.random() < 0.5 else -run
            cx = max(0, min(cols, cx))
            cy = max(0, min(rows, cy))
            points.append((cx * GRID, cy * GRID))
            horizontal = not horizontal
        draw.line(points, fill=ink, width=2, joint="curve")
        for x, y in (points[0], points[-1]):
            draw.ellipse((x - 5, y - 5, x + 5, y + 5), outline=pad, width=2)

    faint = (ink[0], ink[1], ink[2], max(1, TRACE_ALPHA // 2))
    for gx in range(0, WIDTH + 1, GRID * 2):
        for gy in range(0, HEIGHT + 1, GRID * 2):
            draw.point((gx, gy), fill=faint)
    return layer


def vignette(img: Image.Image) -> Image.Image:
    """Fade towards the edges, where the prompt and status line live."""
    mask = Image.new("L", (WIDTH, HEIGHT), 0)
    md = ImageDraw.Draw(mask)
    cx, cy = WIDTH / 2, HEIGHT / 2
    longest = math.hypot(cx, cy)
    steps = 60
    for i in range(steps, 0, -1):
        t = i / steps
        rr = longest * t
        md.ellipse((cx - rr, cy - rr, cx + rr, cy + rr), fill=int(255 * (1 - t * 0.75) ** 0.6))
    mask = mask.filter(ImageFilter.GaussianBlur(80))
    alpha = img.getchannel("A").point(lambda a: a)
    img.putalpha(Image.composite(alpha, Image.new("L", img.size, 0), mask))
    return img


out = Image.alpha_composite(soft_glows(), circuit_traces())
out = vignette(out)

path = __file__.rsplit("/", 1)[0] + "/background.png"
out.quantize(colors=192, method=Image.Quantize.FASTOCTREE)\
   .save(path, optimize=True)

alpha = list(out.getchannel("A").tobytes())
lit = [a for a in alpha if a > 0]
print(f"wrote {path} ({WIDTH}x{HEIGHT})")
print(f"  ink on {len(lit) * 100 / len(alpha):.1f}% of pixels, "
      f"mean alpha {sum(lit) // max(1, len(lit))}/255, peak {max(alpha)}/255")
