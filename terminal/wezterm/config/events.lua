local wezterm = require("wezterm")
local mux = wezterm.mux

-- Re-apply transparency when entering fullscreen (workaround for macOS overriding opacity, wezterm#4925)
-- Values are shared from wezterm.lua via wezterm.GLOBAL
wezterm.on("window-resized", function(window, pane)
  local g = wezterm.GLOBAL or {}
  local opacity_value = g.opacity
  local blur_value = g.blur
  if opacity_value == nil or blur_value == nil then
    return
  end

  local dims = window:get_dimensions()
  local overrides = window:get_config_overrides() or {}
  if dims.is_full_screen then
    if overrides.window_background_opacity ~= opacity_value or overrides.macos_window_background_blur ~= blur_value then
      overrides.window_background_opacity = opacity_value
      overrides.macos_window_background_blur = blur_value
      window:set_config_overrides(overrides)
    end
  else
    if overrides.window_background_opacity ~= nil or overrides.macos_window_background_blur ~= nil then
      overrides.window_background_opacity = nil
      overrides.macos_window_background_blur = nil
      window:set_config_overrides(overrides)
    end
  end
end)

wezterm.on("gui-startup", function(cmd)
  local tab, pane, window = mux.spawn_window(cmd or {})
end)

-- Bell notification (e.g. Claude Code task completed)
wezterm.on("bell", function(window, pane)
  window:toast_notification("Claude Code", "Task completed", nil, 4000)
end)

-- Tab title: folder name + process name (VSCode style)
wezterm.on("format-tab-title", function(tab, tabs, panes, config, hover, max_width)
  local pane = tab.active_pane
  local cwd = pane.current_working_dir
  local title = pane.title

  if cwd then
    local cwd_str = cwd.file_path or tostring(cwd)
    local folder = cwd_str:match("([^/]+)/?$") or cwd_str
    local process = pane.foreground_process_name or ""
    process = process:match("([^/]+)$") or process

    if process == "zsh" or process == "bash" or process == "" then
      title = folder
    else
      title = folder .. " — " .. process
    end
  end

  local index = tab.tab_index + 1
  title = index .. ": " .. wezterm.truncate_right(title, max_width - 6)

  return {
    { Text = " " .. title .. " " },
  }
end)

-- Right status bar: current directory + time (VSCode style)
wezterm.on("update-status", function(window, pane)
  local cwd = pane:get_current_working_dir()
  local cwd_text = ""
  if cwd then
    local cwd_str = cwd.file_path or tostring(cwd)
    local home = os.getenv("HOME") or ""
    cwd_text = cwd_str:gsub("^" .. home:gsub("%-", "%%-"), "~")
  end

  local time = wezterm.strftime("%H:%M")
  local workspace = window:active_workspace() or "default"

  window:set_right_status(wezterm.format({
    { Foreground = { Color = "#888888" } },
    { Text = " [" .. workspace .. "]  " .. cwd_text .. "  " .. time .. " " },
  }))
end)
