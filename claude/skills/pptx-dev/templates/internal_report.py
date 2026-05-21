"""Internal report template: navy/gray, dense text-friendly, Yu Gothic UI 18pt."""
from __future__ import annotations

from pptx.dml.color import RGBColor
from pptx.util import Pt

THEME = {
    "name": "internal_report",
    "font_family": "Yu Gothic UI",
    "font_size_title": 28,
    "font_size_body": 18,
    "font_size_notes": 12,
    "color_text": "#1F1F1F",
    "color_title": "#1F4E79",
    "color_accent": "#2E75B6",
    "color_bg": "#FFFFFF",
    "color_section_bg": "#1F4E79",
    "color_section_text": "#FFFFFF",
    "margin_pt": 32,
}


def _apply_theme(run, theme: dict, size: int, color_hex: str) -> None:
    run.font.name = theme["font_family"]
    run.font.size = Pt(size)
    r, g, b = int(color_hex[1:3], 16), int(color_hex[3:5], 16), int(color_hex[5:7], 16)
    run.font.color.rgb = RGBColor(r, g, b)


def render_slide(slide, spec: dict, theme: dict) -> None:
    """Render a single slide spec onto an existing pptx slide. Mutates slide."""
    from pptx.util import Inches

    layout = spec.get("layout", "content")
    title = spec.get("title", "")

    if layout == "title":
        _render_title(slide, spec, theme)
    elif layout == "section":
        _render_section(slide, spec, theme)
    elif layout == "content":
        _render_content(slide, spec, theme)
    elif layout == "two_column":
        _render_two_column(slide, spec, theme)
    elif layout == "chart":
        _render_chart_placeholder(slide, spec, theme)
    elif layout == "quote":
        _render_quote(slide, spec, theme)
    elif layout == "closing":
        _render_closing(slide, spec, theme)
    else:
        raise ValueError(f"unknown layout: {layout}")

    notes = spec.get("notes", "")
    if notes:
        slide.notes_slide.notes_text_frame.text = notes


def _add_textbox(slide, left, top, width, height, text, theme, size, color):
    from pptx.util import Emu
    box = slide.shapes.add_textbox(Emu(left), Emu(top), Emu(width), Emu(height))
    tf = box.text_frame
    tf.word_wrap = True
    tf.text = text
    for para in tf.paragraphs:
        for run in para.runs:
            _apply_theme(run, theme, size, color)
    return box


def _render_title(slide, spec, theme):
    from pptx.util import Inches
    _add_textbox(slide, Inches(0.8).emu, Inches(2.6).emu, Inches(11.8).emu, Inches(1.5).emu,
                 spec.get("title", ""), theme, theme["font_size_title"] + 8, theme["color_title"])
    subtitle = spec.get("subtitle", "")
    if subtitle:
        _add_textbox(slide, Inches(0.8).emu, Inches(4.2).emu, Inches(11.8).emu, Inches(0.8).emu,
                     subtitle, theme, theme["font_size_body"], theme["color_text"])


def _render_section(slide, spec, theme):
    from pptx.util import Inches
    from pptx.dml.color import RGBColor
    bg = theme["color_section_bg"]
    r, g, b = int(bg[1:3], 16), int(bg[3:5], 16), int(bg[5:7], 16)
    slide.background.fill.solid()
    slide.background.fill.fore_color.rgb = RGBColor(r, g, b)
    _add_textbox(slide, Inches(0.8).emu, Inches(3.0).emu, Inches(11.8).emu, Inches(1.5).emu,
                 spec.get("title", ""), theme, theme["font_size_title"] + 4,
                 theme["color_section_text"])


def _render_content(slide, spec, theme):
    from pptx.util import Inches
    _add_textbox(slide, Inches(0.6).emu, Inches(0.5).emu, Inches(12.2).emu, Inches(0.9).emu,
                 spec.get("title", ""), theme, theme["font_size_title"], theme["color_title"])
    bullets = spec.get("bullets", [])
    if not bullets:
        return
    text = "\n".join(f"• {b}" for b in bullets)
    _add_textbox(slide, Inches(0.6).emu, Inches(1.7).emu, Inches(12.2).emu, Inches(5.3).emu,
                 text, theme, theme["font_size_body"], theme["color_text"])


def _render_two_column(slide, spec, theme):
    from pptx.util import Inches
    _add_textbox(slide, Inches(0.6).emu, Inches(0.5).emu, Inches(12.2).emu, Inches(0.9).emu,
                 spec.get("title", ""), theme, theme["font_size_title"], theme["color_title"])
    left = spec.get("left", {})
    right = spec.get("right", {})
    _add_textbox(slide, Inches(0.6).emu, Inches(1.7).emu, Inches(5.9).emu, Inches(0.6).emu,
                 left.get("heading", ""), theme, theme["font_size_body"] + 2, theme["color_accent"])
    _add_textbox(slide, Inches(0.6).emu, Inches(2.4).emu, Inches(5.9).emu, Inches(4.6).emu,
                 "\n".join(f"• {b}" for b in left.get("bullets", [])),
                 theme, theme["font_size_body"], theme["color_text"])
    _add_textbox(slide, Inches(6.8).emu, Inches(1.7).emu, Inches(5.9).emu, Inches(0.6).emu,
                 right.get("heading", ""), theme, theme["font_size_body"] + 2, theme["color_accent"])
    _add_textbox(slide, Inches(6.8).emu, Inches(2.4).emu, Inches(5.9).emu, Inches(4.6).emu,
                 "\n".join(f"• {b}" for b in right.get("bullets", [])),
                 theme, theme["font_size_body"], theme["color_text"])


def _render_chart_placeholder(slide, spec, theme):
    from pptx.util import Inches
    _add_textbox(slide, Inches(0.6).emu, Inches(0.5).emu, Inches(12.2).emu, Inches(0.9).emu,
                 spec.get("title", ""), theme, theme["font_size_title"], theme["color_title"])
    chart = spec.get("chart", {})
    placeholder = f"[chart: {chart.get('type', 'unknown')} source={chart.get('data_source', 'TBD')}]"
    _add_textbox(slide, Inches(0.6).emu, Inches(1.8).emu, Inches(12.2).emu, Inches(4.6).emu,
                 placeholder, theme, theme["font_size_body"], theme["color_text"])
    annotation = chart.get("annotation", "")
    if annotation:
        _add_textbox(slide, Inches(0.6).emu, Inches(6.5).emu, Inches(12.2).emu, Inches(0.5).emu,
                     annotation, theme, theme["font_size_notes"], theme["color_accent"])


def _render_quote(slide, spec, theme):
    from pptx.util import Inches
    quote = spec.get("quote", "")
    source = spec.get("source", "")
    _add_textbox(slide, Inches(1.5).emu, Inches(2.5).emu, Inches(10.3).emu, Inches(2.5).emu,
                 f"“{quote}”", theme, theme["font_size_title"], theme["color_text"])
    if source:
        _add_textbox(slide, Inches(1.5).emu, Inches(5.2).emu, Inches(10.3).emu, Inches(0.6).emu,
                     f"— {source}", theme, theme["font_size_body"], theme["color_accent"])


def _render_closing(slide, spec, theme):
    from pptx.util import Inches
    _add_textbox(slide, Inches(0.8).emu, Inches(2.8).emu, Inches(11.8).emu, Inches(1.4).emu,
                 spec.get("title", "Thank you"), theme, theme["font_size_title"] + 12,
                 theme["color_title"])
    cta = spec.get("cta", "")
    if cta:
        _add_textbox(slide, Inches(0.8).emu, Inches(4.3).emu, Inches(11.8).emu, Inches(1.0).emu,
                     cta, theme, theme["font_size_body"] + 2, theme["color_accent"])
