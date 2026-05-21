"""Template registry. Templates live as a python package under templates/."""
from __future__ import annotations

import importlib
import sys
from pathlib import Path
from types import ModuleType


SKILL_ROOT = Path(__file__).resolve().parents[2]
TEMPLATES_DIR = SKILL_ROOT / "templates"


def _ensure_path() -> None:
    parent = str(SKILL_ROOT)
    if parent not in sys.path:
        sys.path.insert(0, parent)


def load_template(name: str) -> ModuleType:
    """Load a template module by name (e.g. 'internal_report')."""
    path = TEMPLATES_DIR / f"{name}.py"
    if not path.exists():
        available = sorted(p.stem for p in TEMPLATES_DIR.glob("*.py") if p.stem != "__init__")
        raise ValueError(f"template not found: {name}. available: {', '.join(available)}")
    _ensure_path()
    module = importlib.import_module(f"templates.{name}")
    required_attrs = {"THEME", "render_slide"}
    missing = required_attrs - set(dir(module))
    if missing:
        raise RuntimeError(f"template {name} missing attributes: {missing}")
    return module
