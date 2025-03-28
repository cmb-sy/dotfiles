# Dotfiles

This repository contains configuration files to automatically set up a development environment on macOS.

## Features

- Zsh configuration (including Starship prompt)
- Git configuration
- VSCode configuration
- Cursor configuration
- Installation of necessary software (via Homebrew)
- Installation of applications (via Homebrew)

## Setup Instructions

Follow these steps to set up your environment from scratch:

1. Clone the repository:

```bash
git clone https://github.com/yourusername/dotfiles.git
cd dotfiles
```

2. Install Homebrew packages and applications:

```bash
./setup/brew_install.sh
```

3. Set up your configurations:

```bash
./scripts/install.sh
```
