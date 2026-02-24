-- キーバインド: VSCode風ショートカット + ペイン操作
local wezterm = require("wezterm")
local act = wezterm.action

return {
  -- タブ操作（VSCode風）
  { key = "t", mods = "SUPER", action = act.SpawnTab("CurrentPaneDomain") },
  { key = "w", mods = "SUPER", action = act.CloseCurrentTab { confirm = true } },
  { key = "[", mods = "SUPER|SHIFT", action = act.ActivateTabRelative(-1) },
  { key = "]", mods = "SUPER|SHIFT", action = act.ActivateTabRelative(1) },
  { key = "1", mods = "SUPER", action = act.ActivateTab(0) },
  { key = "2", mods = "SUPER", action = act.ActivateTab(1) },
  { key = "3", mods = "SUPER", action = act.ActivateTab(2) },
  { key = "4", mods = "SUPER", action = act.ActivateTab(3) },
  { key = "5", mods = "SUPER", action = act.ActivateTab(4) },
  { key = "6", mods = "SUPER", action = act.ActivateTab(5) },
  { key = "7", mods = "SUPER", action = act.ActivateTab(6) },
  { key = "8", mods = "SUPER", action = act.ActivateTab(7) },
  { key = "9", mods = "SUPER", action = act.ActivateTab(-1) },
  -- ペイン操作
  { key = "\\", mods = "SUPER", action = act.SplitVertical { domain = "CurrentPaneDomain" } },
  { key = "|", mods = "SUPER|SHIFT", action = act.SplitVertical { domain = "CurrentPaneDomain" } },
  { key = "_", mods = "SUPER|SHIFT", action = act.SplitHorizontal { domain = "CurrentPaneDomain" } },
  { key = "LeftArrow", mods = "SUPER|ALT", action = act.ActivatePaneDirection("Left") },
  { key = "RightArrow", mods = "SUPER|ALT", action = act.ActivatePaneDirection("Right") },
  { key = "UpArrow", mods = "SUPER|ALT", action = act.ActivatePaneDirection("Up") },
  { key = "DownArrow", mods = "SUPER|ALT", action = act.ActivatePaneDirection("Down") },
  { key = "LeftArrow", mods = "CTRL|SHIFT", action = act.AdjustPaneSize { "Left", 3 } },
  { key = "RightArrow", mods = "CTRL|SHIFT", action = act.AdjustPaneSize { "Right", 3 } },
  { key = "UpArrow", mods = "CTRL|SHIFT", action = act.AdjustPaneSize { "Up", 3 } },
  { key = "DownArrow", mods = "CTRL|SHIFT", action = act.AdjustPaneSize { "Down", 3 } },
  { key = "Enter", mods = "SUPER|SHIFT", action = act.TogglePaneZoomState },
  -- フォントサイズ
  { key = "-", mods = "CTRL|SHIFT", action = act.DecreaseFontSize },
  { key = "=", mods = "CTRL|SHIFT", action = act.IncreaseFontSize },
  { key = "0", mods = "SUPER", action = act.ResetFontSize },
  -- コマンドパレット & セッショナイザー
  { key = "p", mods = "SUPER|SHIFT", action = act.ActivateCommandPalette },
  { key = "o", mods = "CTRL|SHIFT", action = act.SpawnCommandInNewTab { args = { "/bin/zsh", "-ic", os.getenv("HOME") .. "/dotfiles/bin/dev" } } },
  -- コピーモード / Quick Select
  { key = "x", mods = "CTRL|SHIFT", action = act.ActivateCopyMode },
  { key = "Space", mods = "CTRL|SHIFT", action = act.QuickSelect },
  -- Claude Code 改行（Shift+Return → \n 送信）
  { key = "Return", mods = "SHIFT", action = act.SendString("\n") },
}
