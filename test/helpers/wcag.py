"""WCAG luminance and contrast, shared by the checks that read template.html.

Reachable from inline `python3 -c` in a .bats file because helpers/common.bash
puts this directory on PYTHONPATH.
"""

import re

_BLOCKS = {
    "dark": r":root\s*\{(.*?)\n  \}",
    "light": r":root\[data-theme=\"light\"\]\s*\{(.*?)\n  \}",
}


def lum(h):
    """Relative luminance of an #rrggbb colour."""
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    c = [(x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4) for x in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def ratio(a, b):
    """Contrast ratio between two #rrggbb colours, 1.0 to 21.0."""
    la, lb = lum(a), lum(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def tokens(css, theme):
    """Hex custom properties declared in the given theme's :root block."""
    block = re.search(_BLOCKS[theme], css, re.S).group(1)
    return dict(re.findall(r"(--[a-z-]+)\s*:\s*(#[0-9a-fA-F]{6})", block))
