-- WezTerm main config (split across config/)
local wezterm = require("wezterm")

local config_dir = wezterm.config_dir

local config = wezterm.config_builder()

-- Appearance (font, theme, window) — loaded first so events.lua can reference values
local appearance = dofile(config_dir .. "/config/appearance.lua")
for k, v in pairs(appearance) do
  config[k] = v
end

-- Share transparency values for the fullscreen workaround in events.lua
wezterm.GLOBAL = wezterm.GLOBAL or {}
wezterm.GLOBAL.opacity = appearance.window_background_opacity
wezterm.GLOBAL.blur = appearance.macos_window_background_blur

-- Event handlers (gui-startup, format-tab-title, etc.)
dofile(config_dir .. "/config/events.lua")

-- Key bindings (includes workspace shortcuts)
config.keys = dofile(config_dir .. "/config/keys.lua")

return config
