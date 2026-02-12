-- WezTerm メイン設定（config/ 以下で分割）
local wezterm = require("wezterm")

local config_dir = wezterm.config_file:match("(.*)/") or "."

-- イベント登録（gui-startup, format-tab-title）
dofile(config_dir .. "/config/events.lua")

-- 設定を組み立て
local config = wezterm.config_builder()

-- 見た目（フォント・テーマ・ウィンドウ）
local appearance = dofile(config_dir .. "/config/appearance.lua")
for k, v in pairs(appearance) do
  config[k] = v
end

-- キーバインド
config.keys = dofile(config_dir .. "/config/keys.lua")

return config
