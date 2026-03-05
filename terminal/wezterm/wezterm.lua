-- WezTerm main config (split across config/)
local wezterm = require("wezterm")

local config_file = wezterm.config_file or ""
local config_dir = config_file:match("(.*)/") or "."
local function try_load(path)
  local f = io.open(path, "r")
  if f then f:close(); return true end
  return false
end
if not try_load(config_dir .. "/config/appearance.lua") then
  local home = os.getenv("HOME")
  if home then
    local alt = home .. "/.config/wezterm"
    if try_load(alt .. "/config/appearance.lua") then config_dir = alt end
  end
end

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
