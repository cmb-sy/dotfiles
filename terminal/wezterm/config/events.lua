local wezterm = require("wezterm")
local mux = wezterm.mux

-- Read opacity/blur from appearance.lua (single source of truth; refreshed on config reload)
local function get_transparency_from_appearance()
  local config_dir = wezterm.config_dir or (wezterm.config_file and wezterm.config_file:match("(.*)/")) or ""
  if config_dir == "" then
    config_dir = (os.getenv("HOME") or "") .. "/.config/wezterm"
    wezterm.log_error("[events.lua] config_dir unknown, using " .. config_dir)
  end
  local path = config_dir .. "/config/appearance.lua"
  local ok, appearance = pcall(dofile, path)
  if not ok then
    wezterm.log_error("[events.lua] Failed to load appearance.lua: " .. tostring(appearance))
    error("[events.lua] appearance.lua load failed: " .. tostring(appearance))
  end
  if type(appearance) ~= "table" then
    wezterm.log_error("[events.lua] appearance.lua did not return a table (got " .. type(appearance) .. ")")
    error("[events.lua] appearance.lua must return a table")
  end
  local opacity = appearance.window_background_opacity
  local blur = appearance.macos_window_background_blur
  if opacity == nil or blur == nil then
    wezterm.log_error("[events.lua] appearance.lua must set window_background_opacity and macos_window_background_blur")
    error("[events.lua] appearance.lua must set window_background_opacity and macos_window_background_blur")
  end
  return opacity, blur
end
local opacity_value, blur_value = get_transparency_from_appearance()

-- Re-apply transparency when entering fullscreen (workaround for macOS overriding opacity, wezterm#4925)
wezterm.on("window-resized", function(window, pane)
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
  window:gui_window():toggle_fullscreen()
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
