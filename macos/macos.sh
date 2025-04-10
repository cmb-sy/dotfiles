#!/bin/sh

# check macOS environment
if [ "$(uname)" != "Darwin" ]; then
  echo 'Not macOS!'
  exit
fi

# ----------------------------------------------------------
# system settings
# ----------------------------------------------------------
sudo nvram SystemAudioVolume=" " # disable startup sound
sudo systemsetup -setrestartfreeze on # do not automatically terminate frozen apps on restart

# ----------------------------------------------------------
# file display settings
# ----------------------------------------------------------
chflags nohidden ~/Library # make ~/Library directory visible
sudo chflags nohidden /Volumes # make /Volumes directory visible

# ----------------------------------------------------------
# Finder settings
# ----------------------------------------------------------
# display items on desktop
defaults write com.apple.finder ShowExternalHardDrivesOnDesktop -bool true
defaults write com.apple.finder ShowHardDrivesOnDesktop -bool true
 # Finderのステータスバー、サイドバー、パスバーを表示
defaults write com.apple.finder ShowMountedServersOnDesktop -bool true
defaults write com.apple.finder ShowStatusBar -bool true
defaults write com.apple.finder ShowSidebar -bool true
defaults write com.apple.finder ShowPathbar -bool true

defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false # disable extension change warning

defaults write com.apple.finder AppleShowAllFiles TRUE # show hidden files

defaults write com.apple.finder WarnOnEmptyTrash -bool false # disable warning before emptying trash

defaults write NSGlobalDomain AppleShowAllExtensions -bool true # show all extensions

defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true # do not create .DS_Store files on network and USB storage
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true # do not create .DS_Store files on network and USB storage
sudo chflags nohidden /Volumes # do not hide /Volumes directory

defaults write -g 'NSRecentDocumentsLimit' -int 0 # do not record recently used items

# ----------------------------------------------------------
# Dock settings
# ----------------------------------------------------------
defaults write com.apple.dock show-recents -bool false # hide recently used apps in menu

# ----------------------------------------------------------
# scroll settings
# ----------------------------------------------------------
defaults write -g AppleShowScrollBars -string "Always" # show scroll bars always

# ----------------------------------------------------------
# keyboard and input settings
# ----------------------------------------------------------
defaults write -g NSAutomaticSpellingCorrectionEnabled -bool false # disable spelling correction

defaults write com.apple.inputmethod.Kotoeri JIMPrefLiveConversionKey -bool false # disable live conversion

# ----------------------------------------------------------
# system dialog settings
# ----------------------------------------------------------
defaults write com.apple.CrashReporter DialogType -string "none" # disable crash report
defaults write com.apple.LaunchServices LSQuarantine -bool false # disable dialog when running unknown apps
defaults write com.apple.LaunchServices LSQuarantine -bool false # disable dialog when opening downloaded files

# ----------------------------------------------------------
# screenshot settings
# ----------------------------------------------------------
defaults write com.apple.screencapture name "SS" # change screenshot file name

# ----------------------------------------------------------
# application settings
# ----------------------------------------------------------
defaults write com.apple.TextEdit RichText -int 0 # use TextEdit as plain text

# ----------------------------------------------------------
# mouse and trackpad settings
# ----------------------------------------------------------
defaults write -g com.apple.mouse.scaling 5.0 # set mouse speed
defaults write -g com.apple.trackpad.scaling 5.0 # set trackpad speed

# ----------------------------------------------------------
# disable hot corners
# ----------------------------------------------------------
defaults write com.apple.dock wvous-bl-corner -int 0
defaults write com.apple.dock wvous-bl-modifier -int 0
defaults write com.apple.dock wvous-br-corner -int 0
defaults write com.apple.dock wvous-br-modifier -int 0
defaults write com.apple.dock wvous-tl-corner -int 0
defaults write com.apple.dock wvous-tl-modifier -int 0
defaults write com.apple.dock wvous-tr-corner -int 0
defaults write com.apple.dock wvous-tr-modifier -int 0

# ----------------------------------------------------------
# restart
# ----------------------------------------------------------
killall Finder
killall Dock