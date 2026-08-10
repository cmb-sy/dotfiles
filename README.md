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
test/                # bats test suite (run with `bats test/`)
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
- no machine-local keys in `.vscode/settings.json`
- the `bats` suite in `test/`

```bash
gh workflow run CI --ref main   # manual trigger
gh run watch                    # tail latest run
```

Reproduce locally:

```bash
CI=true zsh setup/install.zsh
CI=true bats test/
```

`bats test/` runs everything. Two kinds of test skip themselves when `$CI` is
set: those needing a desktop session (a live input source, a real screen) and
the wall-clock budgets, which only mean something on a quiet machine. The suite
is green on a runner without pretending those checks ran there.
