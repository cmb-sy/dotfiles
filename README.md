# Dotfiles

This repository contains configuration files to automatically set up a development environment on macOS.

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
./setup/install.sh
```

4. Restart your terminal to apply all changes

## CI Usage

For continuous integration environments, use:

```bash
CI=true ./setup/install.sh
```

cat ~/.claude/stats-cache.json 2>/dev/null | jq . | head -50
ls ~/.claude/.credentials.json 2>/dev/null && echo "exists" || echo "not found"
security find-generic-password -s 'Claude Code-credentials' -w 2>/dev/null | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null | head -c 20
ls -la ~/.claude/.credentials.json 2>/dev/null | head -3
ln -sf /Users/snakashima/dotfiles/claude/com.snakashima.claude-usage-refresh.plist ~/Library/LaunchAgents/com.snakashima.claude-usage-refresh.plist && launchctl load ~/Library/LaunchAgents/com.snakashima.claude-usage-refresh.plist 2>&1
sleep 3 && cat ~/.cache/claude-statusline-usage.json 2>/dev/null | jq 'keys' 2>/dev/null || echo "キャッシュ未生成"
cat /tmp/claude-usage-refresh.log 2>/dev/null || echo "ログなし"
launchctl list | grep claude
token=$(security find-generic-password -s 'Claude Code-credentials' -w 2>/dev/null | jq -r '.claudeAiOauth.accessToken // empty') && curl -s --max-time 10 "https://api.anthropic.com/api/oauth/usage" -H "Authorization: Bearer $token" -H "anthropic-beta: oauth-2025-04-20" -H "Content-Type: application/json" | jq .
