"""Design proposal template: gray-base with magenta accent, technical/figure-heavy."""
from __future__ import annotations

from . import internal_report as _base


THEME = {
    "name": "design_proposal",
    "font_family": "BIZ UDPGothic",
    "font_size_title": 26,
    "font_size_body": 18,
    "font_size_notes": 12,
    "color_text": "#212121",
    "color_title": "#37474F",
    "color_accent": "#C2185B",
    "color_bg": "#FAFAFA",
    "color_section_bg": "#37474F",
    "color_section_text": "#FFFFFF",
    "margin_pt": 32,
}


def render_slide(slide, spec: dict, theme: dict) -> None:
    """Delegate to internal_report.render_slide with overridden theme."""
    _base.render_slide(slide, spec, theme)
