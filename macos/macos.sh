#!/bin/sh

# macOS環境確認
if [ "$(uname)" != "Darwin" ]; then
  echo 'Not macOS!'
  exit
fi

# ----------------------------------------------------------
# システム設定
# ----------------------------------------------------------
sudo nvram SystemAudioVolume=" " # 起動音を無効化
sudo systemsetup -setrestartfreeze on # 再起動時にフリーズしたアプリを自動的に終了しない

# ----------------------------------------------------------
# ファイル表示設定
# ----------------------------------------------------------
chflags nohidden ~/Library # ~/Library ディレクトリを見えるようにする 
sudo chflags nohidden /Volumes # /Volumes ディレクトリを見えるようにする 

# ----------------------------------------------------------
# Finder設定
# ----------------------------------------------------------
# デスクトップにアイテムを表示
defaults write com.apple.finder ShowExternalHardDrivesOnDesktop -bool true
defaults write com.apple.finder ShowHardDrivesOnDesktop -bool true
 # Finderのステータスバー、サイドバー、パスバーを表示
defaults write com.apple.finder ShowMountedServersOnDesktop -bool true
defaults write com.apple.finder ShowStatusBar -bool true
defaults write com.apple.finder ShowSidebar -bool true
defaults write com.apple.finder ShowPathbar -bool true

defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false # 拡張子変更時の警告を無効化

defaults write com.apple.finder AppleShowAllFiles TRUE # 隠しファイルを表示

defaults write com.apple.finder WarnOnEmptyTrash -bool false # ゴミ箱を空にする前の警告の無効化

defaults write NSGlobalDomain AppleShowAllExtensions -bool true # すべての拡張子を表示

defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true # ネットワークおよびUSBストレージに.DS_Storeファイルを作成しない
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true # ネットワークおよびUSBストレージに.DS_Storeファイルを作成しない
sudo chflags nohidden /Volumes # /Volumesディレクトリを非表示にしない

defaults write -g 'NSRecentDocumentsLimit' -int 0 # 最近使った項目を記録しない

# ----------------------------------------------------------
# Dock設定
# ----------------------------------------------------------
defaults write com.apple.dock show-recents -bool false # メニュー内の最近使ったアプリを非表示

# ----------------------------------------------------------
# スクロール設定
# ----------------------------------------------------------
defaults write -g AppleShowScrollBars -string "Always" # スクロールバーを常時表示

# ----------------------------------------------------------
# キーボードと入力設定
# ----------------------------------------------------------
defaults write -g NSAutomaticSpellingCorrectionEnabled -bool false # スペルの訂正を無効化

defaults write com.apple.inputmethod.Kotoeri JIMPrefLiveConversionKey -bool false # ライブ変換を無効化

# ----------------------------------------------------------
# システムダイアログ設定
# ----------------------------------------------------------
defaults write com.apple.CrashReporter DialogType -string "none" # クラッシュレポートを無効化
defaults write com.apple.LaunchServices LSQuarantine -bool false # 未確認のアプリケーションを実行する際のダイアログを無効化
defaults write com.apple.LaunchServices LSQuarantine -bool false # ダウンロードしたファイルを開くときの警告ダイアログをなくす

# ----------------------------------------------------------
# スクリーンショット設定
# ----------------------------------------------------------
defaults write com.apple.screencapture name "SS" # スクリーンショットのファイル名を変更

# ----------------------------------------------------------
# アプリケーション設定
# ----------------------------------------------------------
defaults write com.apple.TextEdit RichText -int 0 # テキストエディットをプレーンテキストで使う

# ----------------------------------------------------------
# マウスとトラックパッド設定
# ----------------------------------------------------------
defaults write -g com.apple.mouse.scaling 5.0 # マウスの速度設定
defaults write -g com.apple.trackpad.scaling 5.0 # トラックパッドの速度設定

# ----------------------------------------------------------
# ホットコーナーを全て無効化
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
# 再起動
# ----------------------------------------------------------
killall Finder
killall Dock