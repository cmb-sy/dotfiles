-- イベント: 起動時フルスクリーン・タブタイトル・ベル通知
local wezterm = require("wezterm")

-- 起動時にフルスクリーン
wezterm.on("gui-startup", function()
  local tab, pane, window = wezterm.mux.spawn_window({})
  window:gui_window():toggle_fullscreen()
end)

-- ベル通知（Claude Code 完了時など）
wezterm.on("bell", function(window, pane)
  window:toast_notification("Claude Code", "Task completed", nil, 4000)
end)

-- タブタイトルの見た目
wezterm.on("format-tab-title", function(tab, tabs, panes, config, hover, max_width)
  local background = "#5c6d74"
  local foreground = "#FFFFFF"

  if tab.is_active then
    background = "#ae8b2d"
    foreground = "#FFFFFF"
  end

  local title = "   " .. wezterm.truncate_right(tab.active_pane.title, max_width - 1) .. "   "

  return {
    { Background = { Color = background } },
    { Foreground = { Color = foreground } },
    { Text = title },
  }
end)
