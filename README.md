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

## CI

```bash
CI=true zsh setup/install.zsh
```
