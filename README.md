# Dotfiles

Configuration files for setting up a macOS development environment.

## Structure

```
.aliases.sh          # Shell aliases (docker, terraform, claude, etc.)
.function.zsh        # Custom shell functions
.zshrc / .zshenv     # Zsh configuration
.gitignore_global    # Global gitignore
Brewfile             # Homebrew packages & casks
git/                 # .gitconfig
terminal/            # Ghostty, WezTerm configuration
macos/               # macOS system preferences scripts
claude/              # Claude Code configuration (skills, agents, hooks, tools)
bin/                 # Custom scripts
setup/               # Setup scripts
```

## Setup

```bash
git clone https://github.com/cmb-sy/dotfiles.git
cd dotfiles
```

Create symlinks and apply base configuration:

```bash
zsh setup/setup.zsh
```

Install Homebrew packages, VSCode/Cursor extensions, and apply macOS settings:

```bash
zsh setup/install.zsh
```

Restart your terminal to apply all changes.

## Testing

Two-layer verification — see [docs/testing.md](docs/testing.md) for details.

**Layer 1 — GitHub Actions CI** (auto on push):

```bash
gh workflow run CI --ref main
```

Verifies symlinks, Brewfile formulas on PATH, skills inventory, and `settings.json` validity. Runs on `macOS-latest` runner.

**Layer 2 — Clean macOS VM via Tart** (manual, Apple Silicon only):

```bash
bash setup/test-tart.sh
```

Runs `setup.zsh` + the same assertions inside a freshly cloned macOS VM, simulating a brand-new MacBook (no Homebrew, no Xcode, true zero state).

## CI

```bash
CI=true zsh setup/install.zsh
```
