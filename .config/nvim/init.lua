-- 基本オプションの設定
local status_ok, _ = pcall(require, 'options')
if not status_ok then
  print("options module could not be loaded")
end

-- キーマップの設定
status_ok, _ = pcall(require, 'keymaps')
if not status_ok then
  print("keymaps module could not be loaded")
end

-- プラグインの設定
status_ok, _ = pcall(require, 'plugins')
if not status_ok then
  print("plugins module could not be loaded")
end

-- TreeSitterとLSPの設定
status_ok, _ = pcall(require, 'setup.treesitter')
if not status_ok then
  print("treesitter module could not be loaded")
end

status_ok, _ = pcall(require, 'setup.lspconfig')
if not status_ok then
  print("lspconfig module could not be loaded")
end
