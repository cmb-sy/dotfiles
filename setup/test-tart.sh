#!/bin/bash
#
# Run dotfiles setup + assertions inside a clean macOS VM via Tart.
#
# Why: GitHub Actions の macOS runner はプリインストール済みツールがあり
# 「真のクリーン」ではない。Tart で macOS インストール直後相当の VM を
# 起動し、setup.zsh + assertions を走らせて新マシン挙動を検証する。
#
# Prereqs:
#   - Apple Silicon (M1+) Mac
#   - 30GB+ free disk space
#   - Tart 2.0+ (brew install cirruslabs/cli/tart)
#
# Usage:
#   bash setup/test-tart.sh             # run full test
#   bash setup/test-tart.sh --keep      # don't delete VM after test
#   bash setup/test-tart.sh --shell     # drop into VM shell after setup
#
set -euo pipefail

VM_NAME="dotfiles-test"
BASE_IMAGE="ghcr.io/cirruslabs/macos-sequoia-base:latest"
KEEP_VM=0
SHELL_AFTER=0

for arg in "$@"; do
  case "$arg" in
    --keep) KEEP_VM=1 ;;
    --shell) SHELL_AFTER=1; KEEP_VM=1 ;;
    -h|--help)
      sed -n '3,/^set/p' "$0" | sed 's/^#//' | head -20
      exit 0
      ;;
  esac
done

# ----------------------------------------------------------------
# Sanity checks
# ----------------------------------------------------------------
if [[ "$(uname -m)" != "arm64" ]]; then
  echo "ERROR: Tart requires Apple Silicon (arm64). Detected: $(uname -m)" >&2
  exit 1
fi

if ! command -v tart >/dev/null 2>&1; then
  echo "Installing Tart via Homebrew..."
  brew install cirruslabs/cli/tart
fi

# ----------------------------------------------------------------
# Prepare VM
# ----------------------------------------------------------------
echo "[1/5] Pull base image (may take 10-20 min on first run, ~25GB)..."
tart pull "$BASE_IMAGE"

if tart list | awk '{print $2}' | grep -qx "$VM_NAME"; then
  echo "[2/5] Existing VM '$VM_NAME' found. Deleting for clean test..."
  tart stop "$VM_NAME" 2>/dev/null || true
  tart delete "$VM_NAME"
fi

echo "[2/5] Clone base image to '$VM_NAME'..."
tart clone "$BASE_IMAGE" "$VM_NAME"

# Increase resources for parallel brew installs
tart set "$VM_NAME" --cpu 4 --memory 8192

# ----------------------------------------------------------------
# Boot and wait for SSH
# ----------------------------------------------------------------
echo "[3/5] Boot VM (headless)..."
tart run "$VM_NAME" --no-graphics &
TART_PID=$!

cleanup() {
  echo ""
  echo "Cleaning up..."
  tart stop "$VM_NAME" 2>/dev/null || true
  wait "$TART_PID" 2>/dev/null || true
  if [[ "$KEEP_VM" -eq 0 ]]; then
    tart delete "$VM_NAME"
    echo "VM deleted."
  else
    echo "VM kept (--keep). Resume with: tart run $VM_NAME"
  fi
}
trap cleanup EXIT

echo "Waiting for SSH..."
for i in $(seq 1 60); do
  IP=$(tart ip "$VM_NAME" 2>/dev/null || true)
  if [[ -n "$IP" ]] && nc -z -G 2 "$IP" 22 2>/dev/null; then
    echo "SSH ready at $IP"
    break
  fi
  sleep 2
  if [[ "$i" -eq 60 ]]; then
    echo "ERROR: VM did not boot within 120s" >&2
    exit 1
  fi
done

# cirruslabs base image default user: admin / admin
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
SSH="sshpass -p admin ssh $SSH_OPTS admin@$IP"

if ! command -v sshpass >/dev/null 2>&1; then
  echo "Installing sshpass (needed to send password noninteractively)..."
  brew install hudochenkov/sshpass/sshpass
fi

# ----------------------------------------------------------------
# Provision and run dotfiles setup inside VM
# ----------------------------------------------------------------
echo "[4/5] Clone dotfiles + run setup.zsh inside VM..."

$SSH bash -s <<'REMOTE'
set -euo pipefail
export NONINTERACTIVE=1
export CI=true

# Install Homebrew (cirruslabs image does not ship with brew)
if ! command -v brew >/dev/null 2>&1; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# Clone dotfiles (use public clone URL)
if [[ ! -d ~/dotfiles ]]; then
  git clone https://github.com/cmb-sy/dotfiles.git ~/dotfiles
fi
cd ~/dotfiles
git pull

# Run setup
CI=true zsh ./setup/setup.zsh
REMOTE

# ----------------------------------------------------------------
# Run assertions (mirror of .github/workflows/ci.yml)
# ----------------------------------------------------------------
echo "[5/5] Running assertions inside VM..."

$SSH bash -s <<'REMOTE'
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

fail=0
check() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "OK  : $label"
  else
    echo "FAIL: $label"
    fail=$((fail + 1))
  fi
}

# Shell config symlinks
for f in .zshrc .zshenv .aliases.sh .function.zsh .gitignore_global; do
  check "symlink ~/$f" test -L "$HOME/$f"
done

# Claude Code symlinks
check "symlink ~/.claude" test -L "$HOME/.claude"
for asset in CLAUDE.md agents hooks settings.json skills statusline.sh; do
  check "symlink ~/.claude-work/$asset" test -L "$HOME/.claude-work/$asset"
  check "reachable ~/.claude/$asset" test -e "$HOME/.claude/$asset"
done

# .config symlinks
for d in wezterm ghostty; do
  check "symlink ~/.config/$d" test -L "$HOME/.config/$d"
done

# Brewfile formulas
for cmd in gh jq fd fzf sheldon starship uv yarn git mise tmux linear; do
  check "PATH has $cmd" command -v "$cmd"
done

# Skills count
count=$(find "$HOME/.claude/skills" -maxdepth 2 -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')
if [[ "$count" -ge 20 ]]; then
  echo "OK  : skills count = $count"
else
  echo "FAIL: skills count = $count (expected >= 20)"
  fail=$((fail + 1))
fi

# settings.json
check "settings.json valid JSON" jq empty "$HOME/.claude/settings.json"

echo ""
if [[ "$fail" -eq 0 ]]; then
  echo "===> All assertions passed."
else
  echo "===> $fail assertion(s) FAILED."
  exit 1
fi
REMOTE

echo ""
echo "==================================="
echo "Tart VM clean-install test: SUCCESS"
echo "==================================="

if [[ "$SHELL_AFTER" -eq 1 ]]; then
  echo "Dropping into VM shell. Type 'exit' to leave."
  $SSH
fi
