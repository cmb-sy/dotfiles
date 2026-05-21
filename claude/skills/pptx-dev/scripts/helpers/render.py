"""Layout helpers shared across templates."""
from __future__ import annotations

from dataclasses import dataclass
from pptx.util import Emu, Pt


SLIDE_WIDTH_EMU = 12192000   # 16:9 default (13.333 inch)
SLIDE_HEIGHT_EMU = 6858000   # 7.5 inch


@dataclass(frozen=True)
class Rect:
    left: int
    top: int
    width: int
    height: int


def content_area(margin_pt: int) -> Rect:
    """Return the inner rect after applying uniform margin in points."""
    if margin_pt < 0:
        raise ValueError("margin_pt must be non-negative")
    margin = Emu(Pt(margin_pt).emu)
    return Rect(
        left=margin,
        top=margin,
        width=SLIDE_WIDTH_EMU - 2 * margin,
        height=SLIDE_HEIGHT_EMU - 2 * margin,
    )


def hex_to_rgb(value: str) -> tuple[int, int, int]:
    """Convert #RRGGBB to (r, g, b)."""
    v = value.lstrip("#")
    if len(v) != 6:
        raise ValueError(f"invalid hex color: {value}")
    return int(v[0:2], 16), int(v[2:4], 16), int(v[4:6], 16)


def relative_luminance(rgb: tuple[int, int, int]) -> float:
    """WCAG relative luminance."""
    def _c(channel: int) -> float:
        s = channel / 255.0
        return s / 12.92 if s <= 0.03928 else ((s + 0.055) / 1.055) ** 2.4

    r, g, b = (_c(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast_ratio(fg_hex: str, bg_hex: str) -> float:
    """WCAG contrast ratio (1..21)."""
    l1 = relative_luminance(hex_to_rgb(fg_hex))
    l2 = relative_luminance(hex_to_rgb(bg_hex))
    lighter, darker = max(l1, l2), min(l1, l2)
    return (lighter + 0.05) / (darker + 0.05)
