-- キーバインド: ペイン分割など
local wezterm = require("wezterm")

return {
  -- 縦分割: 下に新しいペイン（Cmd+Shift+\）
  { key = "|", mods = "SUPER|SHIFT", action = wezterm.action.SplitVertical { domain = "CurrentPaneDomain" } },
  -- 横分割: 右に新しいペイン（Cmd+Shift+-）
  { key = "-", mods = "SUPER|SHIFT", action = wezterm.action.SplitHorizontal { domain = "CurrentPaneDomain" } },
}
