-- キーバインド: ペイン分割など
local wezterm = require("wezterm")

return {
  -- フォントサイズ（Ctrl+Shift+- で減らす / Ctrl+Shift+= で増やす）
  { key = "-", mods = "CTRL|SHIFT", action = wezterm.action.DecreaseFontSize },
  { key = "=", mods = "CTRL|SHIFT", action = wezterm.action.IncreaseFontSize },
  -- 縦分割: 下に新しいペイン（Cmd+Shift+\）
  { key = "|", mods = "SUPER|SHIFT", action = wezterm.action.SplitVertical { domain = "CurrentPaneDomain" } },
  -- 横分割: 右に新しいペイン（Cmd+Shift+-）
  { key = "-", mods = "SUPER|SHIFT", action = wezterm.action.SplitHorizontal { domain = "CurrentPaneDomain" } },
}
