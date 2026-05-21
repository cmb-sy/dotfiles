"""LT/social talk template: high-contrast, large fonts, generous whitespace."""
from __future__ import annotations

from . import internal_report as _base


THEME = {
    "name": "lt_talk",
    "font_family": "Yu Gothic UI",
    "font_size_title": 36,
    "font_size_body": 24,
    "font_size_notes": 14,
    "color_text": "#0D0D0D",
    "color_title": "#E65100",
    "color_accent": "#FF6F00",
    "color_bg": "#FFFFFF",
    "color_section_bg": "#0D0D0D",
    "color_section_text": "#FFD54F",
    "margin_pt": 48,
}


def render_slide(slide, spec: dict, theme: dict) -> None:
    """Delegate to internal_report.render_slide with LT-tuned theme."""
    _base.render_slide(slide, spec, theme)
