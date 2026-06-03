#!/usr/bin/env python3
"""Idempotent writer for Handy's post-processing config in settings_store.json.

Handy OWNS this file and rewrites it from in-memory state while running, so any
external edit is clobbered unless Handy is fully quit first. This script refuses
to run while Handy is alive (override with HANDY_APPLY_FORCE=1). bin/handy-switch
does the quit -> apply -> relaunch dance; call this through that, not directly.

Cloud post-processing targets Cerebras, which is privacy-acceptable because it
neither RETAINS nor TRAINS on request data:
  - no retention: https://support.cerebras.net/articles/1811589793-does-cerebras-retain-my-data
    ("We do not retain ... Prompt content, API requests or responses ... User input or model output")
  - no training:  https://www.cerebras.ai/terms-of-service
    ("Cerebras does not grant itself the right to use Service Content for ... training or fine-tuning models")
US text transmission is acceptable per the user; data-training is the hard no-go.
The Cerebras API key is NEVER stored in this repo: it arrives via the CEREBRAS_API_KEY
env var (read from the macOS Keychain by handy-switch) and lands only in the
app-owned settings_store.json outside the repo.
"""
import argparse
import json
import os
import pathlib
import subprocess
import sys

SETTINGS = pathlib.Path.home() / "Library/Application Support/com.pais.handy/settings_store.json"
PROMPT_FILE = pathlib.Path(__file__).resolve().parent / "ja_light_tidy.prompt.txt"
PROMPT_ID = "ja_light_tidy"
PROMPT_NAME = "JP Light Tidy"
LOCAL_MODEL = "qwen3:4b-instruct-2507-q4_K_M"
# Cerebras catalog is volatile (llama-3.3-70b and qwen-* were removed). As of 2026-06-03 the
# free account exposes only gpt-oss-120b (prod) and zai-glm-4.7 (preview); verify anytime with
#   curl https://api.cerebras.ai/v1/models -H "Authorization: Bearer $CEREBRAS_API_KEY"
# gpt-oss-120b chosen as default: shorter reasoning, faithful JP light-tidy, prod-tier.
# Swap to zai-glm-4.7 via --model (note: it reasons verbosely and can hit token limits).
DEFAULT_CLOUD_MODEL = "gpt-oss-120b"
# Rebind "cancel current recording" from the default Escape to the C key.
# Safe: Handy registers the cancel hotkey only while recording and unregisters it on stop
# (src-tauri/src/shortcut/handler.rs "only fires when recording"), so typing "c" normally is
# untouched when not dictating. "c" is the handy_keys string for the C key per
# src/lib/utils/keyboard.ts (KeyC -> "c"). Chosen over Backspace because external keyboards'
# "delete" key did not cancel.
CANCEL_BINDING = "c"


def die(msg: str) -> "NoReturn":
    print(f"apply-settings: {msg}", file=sys.stderr)
    sys.exit(1)


def handy_running() -> bool:
    return subprocess.run(["/usr/bin/pgrep", "-x", "handy"],
                          capture_output=True).returncode == 0


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--provider", choices=["local", "cloud"], required=True)
    ap.add_argument("--model", default=None, help="override cloud model id")
    args = ap.parse_args()

    if handy_running() and os.environ.get("HANDY_APPLY_FORCE") != "1":
        die("Handy is running; quit it first (handy-switch does this) or set HANDY_APPLY_FORCE=1")
    if not SETTINGS.exists():
        die(f"settings_store.json not found: {SETTINGS}")
    if not PROMPT_FILE.exists():
        die(f"prompt file not found: {PROMPT_FILE}")

    prompt = PROMPT_FILE.read_text(encoding="utf-8").rstrip("\n")
    data = json.loads(SETTINGS.read_text(encoding="utf-8"))
    s = data.get("settings", data)

    # 1. Upsert the JP light-tidy prompt and select+enable it.
    prompts = s.setdefault("post_process_prompts", [])
    for pr in prompts:
        if pr.get("id") == PROMPT_ID:
            pr["prompt"] = prompt
            pr["name"] = PROMPT_NAME
            break
    else:
        prompts.append({"id": PROMPT_ID, "name": PROMPT_NAME, "prompt": prompt})
    s["post_process_selected_prompt_id"] = PROMPT_ID
    s["post_process_enabled"] = True

    # 2. Rebind the cancel-recording key (recording-scoped, so it never clobbers Backspace).
    bindings = s.get("bindings")
    if isinstance(bindings, dict) and isinstance(bindings.get("cancel"), dict):
        bindings["cancel"]["current_binding"] = CANCEL_BINDING

    # 3. Point provider + model + key.
    models = s.setdefault("post_process_models", {})
    keys = s.setdefault("post_process_api_keys", {})
    if args.provider == "local":
        s["post_process_provider_id"] = "custom"  # base_url http://localhost:11434/v1 (ollama)
        models["custom"] = LOCAL_MODEL
        if not keys.get("custom"):
            keys["custom"] = "ollama"  # dummy bearer; ollama ignores it but OpenAI-compat needs one
    else:
        model = args.model or DEFAULT_CLOUD_MODEL
        key = os.environ.get("CEREBRAS_API_KEY", "").strip()
        if not key:
            die("CEREBRAS_API_KEY not set (handy-switch reads it from the Keychain)")
        s["post_process_provider_id"] = "cerebras"  # base_url https://api.cerebras.ai/v1 (fixed)
        models["cerebras"] = model
        keys["cerebras"] = key

    SETTINGS.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    pid = s["post_process_provider_id"]
    print(f"apply-settings: provider={pid} model={models.get(pid)} prompt={PROMPT_ID} enabled=True")


if __name__ == "__main__":
    main()
