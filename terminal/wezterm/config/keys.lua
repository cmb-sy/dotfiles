-- Key bindings: VSCode-style shortcuts, panes, workspaces
local wezterm = require("wezterm")
local act = wezterm.action

return {
  -- Cmd+Shift+S / Leader+s: workspace list
  { key = "s", mods = "SUPER|SHIFT", action = act.ShowLauncherArgs { flags = "WORKSPACES", title = "Select workspace" } },
  -- Cmd+Shift+C: create/switch workspace by name (prompt)
  {
    key = "c",
    mods = "SUPER|SHIFT",
    action = act.PromptInputLine {
      description = "(wezterm) Create new workspace:",
      action = wezterm.action_callback(function(window, pane, line)
        if line and #line > 0 then
          window:perform_action(act.SwitchToWorkspace { name = line }, pane)
        end
      end),
    },
  },
  -- Tab operations (VSCode style)
  { key = "t", mods = "SUPER", action = act.SpawnTab("CurrentPaneDomain") },
  { key = "w", mods = "SUPER", action = act.CloseCurrentTab { confirm = false } },
  { key = "[", mods = "SUPER|SHIFT", action = act.ActivateTabRelative(-1) },
  { key = "]", mods = "SUPER|SHIFT", action = act.ActivateTabRelative(1) },
  { key = "1", mods = "SUPER", action = act.ActivateTab(0) },
  { key = "2", mods = "SUPER", action = act.ActivateTab(1) },
  { key = "3", mods = "SUPER", action = act.ActivateTab(2) },
  { key = "4", mods = "SUPER", action = act.ActivateTab(3) },
  { key = "5", mods = "SUPER", action = act.ActivateTab(4) },
  { key = "6", mods = "SUPER", action = act.ActivateTab(5) },
  { key = "7", mods = "SUPER", action = act.ActivateTab(6) },
  { key = "8", mods = "SUPER", action = act.ActivateTab(7) },
  { key = "9", mods = "SUPER", action = act.ActivateTab(-1) },
  -- Panes
  { key = "\\", mods = "SUPER", action = act.SplitVertical { domain = "CurrentPaneDomain" } },
  { key = "|", mods = "SUPER|SHIFT", action = act.SplitVertical { domain = "CurrentPaneDomain" } },
  { key = "_", mods = "SUPER|SHIFT", action = act.SplitHorizontal { domain = "CurrentPaneDomain" } },
  { key = "LeftArrow", mods = "SUPER|ALT", action = act.ActivatePaneDirection("Left") },
  { key = "RightArrow", mods = "SUPER|ALT", action = act.ActivatePaneDirection("Right") },
  { key = "UpArrow", mods = "SUPER|ALT", action = act.ActivatePaneDirection("Up") },
  { key = "DownArrow", mods = "SUPER|ALT", action = act.ActivatePaneDirection("Down") },
  { key = "LeftArrow", mods = "CTRL|SHIFT", action = act.AdjustPaneSize { "Left", 3 } },
  { key = "RightArrow", mods = "CTRL|SHIFT", action = act.AdjustPaneSize { "Right", 3 } },
  { key = "UpArrow", mods = "CTRL|SHIFT", action = act.AdjustPaneSize { "Up", 3 } },
  { key = "DownArrow", mods = "CTRL|SHIFT", action = act.AdjustPaneSize { "Down", 3 } },
  { key = "Enter", mods = "SUPER|SHIFT", action = act.TogglePaneZoomState },
  -- Window: toggle fullscreen (expand workspace window)
  { key = "f", mods = "SUPER|CTRL", action = act.ToggleFullScreen },
  -- Font size
  { key = "-", mods = "CTRL|SHIFT", action = act.DecreaseFontSize },
  { key = "=", mods = "CTRL|SHIFT", action = act.IncreaseFontSize },
  { key = "0", mods = "SUPER", action = act.ResetFontSize },
  -- Command palette & session launcher
  { key = "p", mods = "SUPER|SHIFT", action = act.ActivateCommandPalette },
  { key = "o", mods = "CTRL|SHIFT", action = act.SpawnCommandInNewTab { args = { "/bin/zsh", "-ic", os.getenv("HOME") .. "/dotfiles/bin/dev" } } },
  -- Copy mode / Quick Select
  { key = "x", mods = "CTRL|SHIFT", action = act.ActivateCopyMode },
  { key = "Space", mods = "CTRL|SHIFT", action = act.QuickSelect },
  -- Claude Code: Shift+Return sends newline
  { key = "Return", mods = "SHIFT", action = act.SendString("\n") },
}
