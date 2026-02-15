-- キーバインド: VSCode風ショートカット + ペイン操作
local wezterm = require("wezterm")
local act = wezterm.action

return {
  -- ══════════════════════════════════════════════════════════
  -- タブ操作（VSCode風）
  -- ══════════════════════════════════════════════════════════
  -- 新しいタブ（Cmd+T）
  { key = "t", mods = "SUPER", action = act.SpawnTab("CurrentPaneDomain") },
  -- タブを閉じる（Cmd+W）
  { key = "w", mods = "SUPER", action = act.CloseCurrentTab { confirm = true } },
  -- タブ切替（Cmd+Shift+[ / ]）
  { key = "[", mods = "SUPER|SHIFT", action = act.ActivateTabRelative(-1) },
  { key = "]", mods = "SUPER|SHIFT", action = act.ActivateTabRelative(1) },
  -- タブ番号で直接切替（Cmd+1〜9）
  { key = "1", mods = "SUPER", action = act.ActivateTab(0) },
  { key = "2", mods = "SUPER", action = act.ActivateTab(1) },
  { key = "3", mods = "SUPER", action = act.ActivateTab(2) },
  { key = "4", mods = "SUPER", action = act.ActivateTab(3) },
  { key = "5", mods = "SUPER", action = act.ActivateTab(4) },
  { key = "6", mods = "SUPER", action = act.ActivateTab(5) },
  { key = "7", mods = "SUPER", action = act.ActivateTab(6) },
  { key = "8", mods = "SUPER", action = act.ActivateTab(7) },
  { key = "9", mods = "SUPER", action = act.ActivateTab(-1) },

  -- ══════════════════════════════════════════════════════════
  -- ペイン操作
  -- ══════════════════════════════════════════════════════════
  -- 縦分割: Cmd+\
  { key = "\\", mods = "SUPER", action = act.SplitVertical { domain = "CurrentPaneDomain" } },
  -- 縦分割: Cmd+Shift+|
  { key = "|", mods = "SUPER|SHIFT", action = act.SplitVertical { domain = "CurrentPaneDomain" } },
  -- 横分割: Cmd+Shift+- (WezTermはShift+-を"_"として認識する)
  { key = "_", mods = "SUPER|SHIFT", action = act.SplitHorizontal { domain = "CurrentPaneDomain" } },
  -- ペイン間移動
  { key = "LeftArrow", mods = "SUPER|ALT", action = act.ActivatePaneDirection("Left") },
  { key = "RightArrow", mods = "SUPER|ALT", action = act.ActivatePaneDirection("Right") },
  { key = "UpArrow", mods = "SUPER|ALT", action = act.ActivatePaneDirection("Up") },
  { key = "DownArrow", mods = "SUPER|ALT", action = act.ActivatePaneDirection("Down") },
  -- ペインサイズ調整（Ctrl+Shift+矢印）
  { key = "LeftArrow", mods = "CTRL|SHIFT", action = act.AdjustPaneSize { "Left", 3 } },
  { key = "RightArrow", mods = "CTRL|SHIFT", action = act.AdjustPaneSize { "Right", 3 } },
  { key = "UpArrow", mods = "CTRL|SHIFT", action = act.AdjustPaneSize { "Up", 3 } },
  { key = "DownArrow", mods = "CTRL|SHIFT", action = act.AdjustPaneSize { "Down", 3 } },
  -- ペインズーム（Cmd+Shift+Enter: VSCodeのターミナル最大化風）
  { key = "Enter", mods = "SUPER|SHIFT", action = act.TogglePaneZoomState },

  -- ══════════════════════════════════════════════════════════
  -- フォントサイズ
  -- ══════════════════════════════════════════════════════════
  { key = "-", mods = "CTRL|SHIFT", action = act.DecreaseFontSize },
  { key = "=", mods = "CTRL|SHIFT", action = act.IncreaseFontSize },
  { key = "0", mods = "SUPER", action = act.ResetFontSize },

  -- ══════════════════════════════════════════════════════════
  -- コマンドパレット & セッショナイザー
  -- ══════════════════════════════════════════════════════════
  -- WezTerm コマンドパレット（Cmd+Shift+P）
  { key = "p", mods = "SUPER|SHIFT", action = act.ActivateCommandPalette },
  -- プロジェクトセッショナイザー（Ctrl+Shift+O）
  {
    key = "o",
    mods = "CTRL|SHIFT",
    action = act.SpawnCommandInNewTab {
      args = { "/bin/zsh", "-ic", os.getenv("HOME") .. "/dotfiles/bin/dev" },
    },
  },

  -- ══════════════════════════════════════════════════════════
  -- その他便利系
  -- ══════════════════════════════════════════════════════════
  -- コピーモード / Quick Select（URLやパスを素早く選択）
  { key = "x", mods = "CTRL|SHIFT", action = act.ActivateCopyMode },
  { key = "Space", mods = "CTRL|SHIFT", action = act.QuickSelect },
}
