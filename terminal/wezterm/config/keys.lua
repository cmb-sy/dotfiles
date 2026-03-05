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
  { key = "[", mods = "SUPER|SHIFT", action = act.ActivateTabRelative(-1) },
  { key = "]", mods = "SUPER|SHIFT", action = act.ActivateTabRelative(1) },

  -- Panes
  { key = "|", mods = "SUPER|SHIFT", action = act.SplitVertical { domain = "CurrentPaneDomain" } },
  { key = "_", mods = "SUPER|SHIFT", action = act.SplitHorizontal { domain = "CurrentPaneDomain" } },

  -- Search: scrollback
  { key = "f", mods = "SUPER", action = act.Search("CurrentSelectionOrEmptyString") },
  { key = "f", mods = "SUPER|SHIFT", action = act.SendString("\x1b[25~") },
  { key = "f", mods = "SUPER|ALT", action = act.SendString("\x1b[25~") },
}
