local wezterm = require("wezterm")

return {
  automatically_reload_config = true,

  -- Font
  font = wezterm.font("SF Mono"),
  font_size = 16,

  -- Color Scheme
  color_scheme = "One Dark (Gogh)",

  -- Window
  window_decorations = "NONE",
  window_background_opacity = 0.80,
  macos_window_background_blur = 10,
  window_frame = {
    inactive_titlebar_bg = "none",
    active_titlebar_bg = "none",
  },
  window_background_gradient = {
    colors = { "#000000" },
  },

  -- Bell
  audible_bell = "Disabled",

  -- Tab Bar
  show_new_tab_button_in_tab_bar = false,
}
