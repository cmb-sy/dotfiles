#!/usr/bin/env bats
# Static checks for macos/macos.sh and the package/editor manifests setup reads.

load "helpers/common"

# Dictation grabs the same hotkeys as Handy, so a fresh Mac must turn all of it
# off. Matched on uncommented lines so a disabled setting fails.
code_of() { grep -v '^[[:space:]]*#' "$REPO_DIR/$1"; }

@test "macos.sh は Dictation の自動有効化を OFF にする" {
  code_of macos/macos.sh | grep -qF 'defaults write com.apple.HIToolbox AppleDictationAutoEnable -bool false'
}

@test "macos.sh は assistant.support の Dictation を OFF にする" {
  code_of macos/macos.sh | grep -qF "defaults write com.apple.assistant.support 'Dictation Enabled' -bool false"
}

@test "macos.sh は DictationIM の LaunchAgent を無効化する" {
  code_of macos/macos.sh | grep -qF 'launchctl disable "gui/$(id -u)/com.apple.DictationIM"'
}

@test "Brewfile は setup が前提にする VS Code・Hack Nerd Font・shellcheck を持つ" {
  code_of Brewfile | grep -qF "cask 'visual-studio-code'"
  code_of Brewfile | grep -qF "cask 'font-hack-nerd-font'"
  code_of Brewfile | grep -qF "brew 'shellcheck'"
}

@test "VS Code 拡張は実在する OneDark テーマ ID を使う" {
  code_of .vscode/extensions.zsh | grep -qE '^akamud\.vscode-theme-onedark([[:space:]]|$)'
  hits=$(code_of .vscode/extensions.zsh | grep -cF 'onedarkpro-darker') || hits=0
  [ "$hits" -eq 0 ]
}

@test "gitconfig は core.editor を決め打ちしない" {
  hits=$(code_of git/.gitconfig | grep -cE '^[[:space:]]*editor[[:space:]]*=') || hits=0
  [ "$hits" -eq 0 ]
}

@test "bin/dev に未使用の project_name が残っていない" {
  hits=$(code_of bin/dev | grep -cF 'project_name') || hits=0
  [ "$hits" -eq 0 ]
}
