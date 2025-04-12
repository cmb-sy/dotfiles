-- TreeSitterの設定
-- プラグインがインストールされていない場合はエラーを出さないようにする
local status_ok, configs = pcall(require, "nvim-treesitter.configs")
if not status_ok then
  return
end

configs.setup({
  ensure_installed = { "lua", "vim", "vimdoc", "javascript", "typescript", "python", "bash" },
  auto_install = true,
  highlight = {
    enable = true,
    additional_vim_regex_highlighting = false,
  },
  indent = {
    enable = true,
  },
}) 