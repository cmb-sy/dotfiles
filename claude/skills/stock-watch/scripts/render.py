#!/usr/bin/env python3
"""Render Markdown stock report to PDF via weasyprint."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import markdown
from weasyprint import HTML, CSS


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Markdown → PDF via weasyprint")
    p.add_argument("--input", type=Path, required=True, help="report.md path")
    p.add_argument("--css", type=Path, required=True, help="report.css path")
    p.add_argument("--output", type=Path, required=True, help="output PDF path")
    p.add_argument("--title", default="Stock Watch Report")
    return p.parse_args()


def main() -> int:
    args = parse_args()
    md_text = args.input.read_text(encoding="utf-8")
    html_body = markdown.markdown(
        md_text,
        extensions=["tables", "fenced_code", "toc", "sane_lists"],
    )
    html_doc = f"""<!doctype html>
<html lang="ja">
<head>
  <meta charset="utf-8">
  <title>{args.title}</title>
</head>
<body>
{html_body}
</body>
</html>"""

    args.output.parent.mkdir(parents=True, exist_ok=True)
    HTML(string=html_doc).write_pdf(
        str(args.output),
        stylesheets=[CSS(filename=str(args.css))],
    )
    print(f"rendered: {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
