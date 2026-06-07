# Dotfiles

Configuration files for setting up a macOS development environment.

## Structure

```
.aliases.sh          # Shell aliases (docker, terraform, claude, etc.)
.function.zsh        # Custom shell functions
.zshrc / .zshenv     # Zsh configuration
.config/             # XDG config (starship prompt)
.gitignore_global    # Global gitignore
Brewfile             # Homebrew packages & casks
git/                 # .gitconfig
terminal/            # Ghostty, WezTerm, cmux configuration
macos/               # macOS system preferences scripts
karabiner/           # Karabiner-Elements config
handy/               # Voice input (Handy + ollama) post-processing config
claude/              # Claude Code configuration (skills, agents, hooks)
bin/                 # Custom scripts
setup/               # Setup scripts
docs/                # Architecture notes & learnings
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

## CI

GitHub Actions runs `setup/setup.zsh` on a `macOS-latest` runner on every push and on a monthly cron schedule, then verifies:

- shell config / Claude Code / `.config` symlinks
- Brewfile formulas on PATH (gh, jq, starship, uv, mise, ...)
- `~/.claude/skills` SKILL.md inventory (≥ 20)
- `~/.claude/settings.json` is valid JSON
- no legacy bad symlinks (`~/.git`, `~/.Brewfile`, etc.)

```bash
gh workflow run CI --ref main   # manual trigger
gh run watch                    # tail latest run
```

Reproduce locally:

```bash
CI=true zsh setup/install.zsh
```
