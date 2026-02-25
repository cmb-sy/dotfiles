local wezterm = require("wezterm")

return {
  automatically_reload_config = true,

  -- Leader key (e.g. Ctrl+b then s = workspace launcher)
  leader = { key = "b", mods = "CTRL" },

  -- Font
  font = wezterm.font("JetBrains Mono"),
  font_size = 16,

  -- Color Scheme (VSCode Dark+ 風)
  color_scheme = "One Dark (Gogh)",

  -- Window（TITLE | RESIZE で閉じる・最小化・最大化ボタンとタブバーを表示）
  window_decorations = "INTEGRATED_BUTTONS | RESIZE",
  window_background_opacity = 0.80,
  macos_window_background_blur = 10,
  window_background_gradient = {
    colors = { "#000000" },
  },
  window_padding = {
    left = 8,
    right = 8,
    top = 8,
    bottom = 4,
  },

  -- macOS: 独立Desktopを作らずに現在のデスクトップ上でフルスクリーン
  native_macos_fullscreen_mode = true,

  -- Bell
  audible_bell = "Disabled",

  -- Tab Bar（VSCode風: 上部に表示、Fancy スタイル）
  use_fancy_tab_bar = true,
  tab_bar_at_bottom = false,
  hide_tab_bar_if_only_one_tab = false,
  show_new_tab_button_in_tab_bar = true,
  tab_max_width = 32,
  window_frame = {
    font = wezterm.font("JetBrains Mono", { weight = "Medium" }),
    font_size = 12,
    inactive_titlebar_bg = "#1e1e1e",
    active_titlebar_bg = "#1e1e1e",
    inactive_titlebar_fg = "#888888",
    active_titlebar_fg = "#cccccc",
    inactive_titlebar_border_bottom = "#1e1e1e",
    active_titlebar_border_bottom = "#1e1e1e",
    button_fg = "#cccccc",
    button_bg = "#1e1e1e",
    button_hover_fg = "#ffffff",
    button_hover_bg = "#333333",
  },
  colors = {
    tab_bar = {
      background = "#1e1e1e",
      active_tab = {
        bg_color = "#1e1e1e",
        fg_color = "#ffffff",
        intensity = "Bold",
      },
      inactive_tab = {
        bg_color = "#2d2d2d",
        fg_color = "#888888",
      },
      inactive_tab_hover = {
        bg_color = "#333333",
        fg_color = "#cccccc",
      },
      new_tab = {
        bg_color = "#1e1e1e",
        fg_color = "#888888",
      },
      new_tab_hover = {
        bg_color = "#333333",
        fg_color = "#ffffff",
      },
    },
  },

  -- Inactive panes (VSCode風: 非アクティブペインを少し暗く)
  inactive_pane_hsb = {
    saturation = 0.8,
    brightness = 0.6,
  },
}
