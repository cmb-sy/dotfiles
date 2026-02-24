-- イベント: 起動時フルスクリーン・タブタイトル・ステータスバー・ベル通知
local wezterm = require("wezterm")

-- 起動時にフルスクリーン
wezterm.on("gui-startup", function()
  local tab, pane, window = wezterm.mux.spawn_window({})
  window:gui_window():toggle_fullscreen()
end)

-- ベル通知（Claude Code 完了時など）
wezterm.on("bell", function(window, pane)
  window:toast_notification("Claude Code", "Task completed", nil, 4000)
end)

-- タブタイトル: VSCode風にフォルダ名 + プロセス名を表示
wezterm.on("format-tab-title", function(tab, tabs, panes, config, hover, max_width)
  -- カレントディレクトリからフォルダ名を取得
  local pane = tab.active_pane
  local cwd = pane.current_working_dir
  local title = pane.title

  if cwd then
    local cwd_str = cwd.file_path or tostring(cwd)
    -- ホームディレクトリの最後のフォルダ名
    local folder = cwd_str:match("([^/]+)/?$") or cwd_str
    -- プロセス名
    local process = pane.foreground_process_name or ""
    process = process:match("([^/]+)$") or process

    if process == "zsh" or process == "bash" or process == "" then
      title = folder
    else
      title = folder .. " — " .. process
    end
  end

  -- タブ番号を付与（VSCode風）
  local index = tab.tab_index + 1
  title = index .. ": " .. wezterm.truncate_right(title, max_width - 6)

  return {
    { Text = " " .. title .. " " },
  }
end)

-- 右ステータスバー: 現在のディレクトリ + 時刻（VSCodeのステータスバー風）
wezterm.on("update-status", function(window, pane)
  local cwd = pane:get_current_working_dir()
  local cwd_text = ""
  if cwd then
    local cwd_str = cwd.file_path or tostring(cwd)
    -- ~/... に短縮
    local home = os.getenv("HOME") or ""
    cwd_text = cwd_str:gsub("^" .. home:gsub("%-", "%%-"), "~")
  end

  local time = wezterm.strftime("%H:%M")

  window:set_right_status(wezterm.format({
    { Foreground = { Color = "#888888" } },
    { Text = " " .. cwd_text .. "  " .. time .. " " },
  }))
end)
