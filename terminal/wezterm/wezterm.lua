-- WezTerm main config (split across config/)
local wezterm = require("wezterm")

local config_dir = wezterm.config_file:match("(.*)/") or "."

-- Event handlers (gui-startup, format-tab-title, etc.)
dofile(config_dir .. "/config/events.lua")

local config = wezterm.config_builder()

-- Appearance (font, theme, window)
local appearance = dofile(config_dir .. "/config/appearance.lua")
for k, v in pairs(appearance) do
  config[k] = v
end

-- Key bindings (includes workspace shortcuts)
config.keys = dofile(config_dir .. "/config/keys.lua")

return config
