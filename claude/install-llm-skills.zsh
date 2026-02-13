#!/bin/zsh

source "${HOME}/dotfiles/setup/util.zsh" 2>/dev/null || source "$(cd "$(dirname "$0")/../setup" && pwd)/util.zsh"

util::info 'Configuring LLM skills (npx skills add)...'

SKILLS=(
  "vercel-labs/agent-skills --skill vercel-react-best-practices --skill vercel-composition-patterns --skill web-design-guidelines"
  "vercel-labs/agent-browser --skill agent-browser"
  "obra/superpowers"
  "anthropics/skills --skill xlsx --skill docx --skill pptx --skill pdf"
  "wshobson/agents --skill backend-development --skill code-review-ai --skill security-scanning --skill full-stack-orchestration --skill code-documentation --skill code-refactoring --skill javascript-typescript"
  "boristane/agent-skills --skill logging-best-practices"
  "intellectronica/agent-skills --skill context7"
)

for spec in "${SKILLS[@]}"; do
  util::info "Installing: $spec"
  eval "npx --yes skills add $spec --yes --global"
done

util::info 'LLM skills install done.'
