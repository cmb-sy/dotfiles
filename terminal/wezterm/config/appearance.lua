local wezterm = require("wezterm")

return {
  automatically_reload_config = true,

  -- Font
  font = wezterm.font("Menlo"),
  font_size = 16,

  -- Color Scheme 
  color_scheme = "One Dark (Gogh)",

  -- Window
  window_decorations = "INTEGRATED_BUTTONS|RESIZE",
  -- Transparency: use native_macos_fullscreen_mode = false so these apply in fullscreen too.
  window_background_opacity = 0.80,
  macos_window_background_blur = 10,
  -- No window_background_gradient: it can prevent opacity/blur from applying.
  window_padding = {
    left = 8,
    right = 8,
    top = 8,
    bottom = 4,
  },

  -- macOS fullscreen
  native_macos_fullscreen_mode = false,

  -- Bell
  audible_bell = "Disabled",
}
