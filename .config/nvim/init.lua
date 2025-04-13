-- バックアップ・スワップファイルを作らない
vim.opt.backup = false
vim.opt.swapfile = false
-- 行番号の表示
vim.opt.number = true
-- 検索を使いやすくする
vim.opt.incsearch = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.hlsearch = true
-- クリップボードを他のアプリと共有
vim.opt.clipboard = "unnamedplus"
-- マウス対応
vim.opt.mouse = "a"
-- 行末で→で次の行へ行ける、など
vim.opt.whichwrap = "b,s,h,l,<,>,[,],~"
-- 行末にiで入れるよう、一文字だけはみ出して移動できるようにする
vim.opt.virtualtext = "onemore"

-- lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", 
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- プラグイン設定
require("lazy").setup({
  -- ファイルエクスプローラー
  {
    "nvim-tree/nvim-tree.lua",
    dependencies = {
      "nvim-tree/nvim-web-devicons",
    },
    config = function()
      -- v2.0.0以降の必須設定
      vim.g.loaded_netrw = 1
      vim.g.loaded_netrwPlugin = 1
      
      require("nvim-tree").setup({
        sort_by = "case_sensitive",
        view = {
          width = 30,
        },
        renderer = {
          indent_markers = {
            enable = true,
          },
          icons = {
            show = {
              file = true,
              folder = true,
              folder_arrow = true,
              git = true,
            },
          },
        },
        filters = {
          dotfiles = false,
        },
        on_attach = function(bufnr)
          local api = require("nvim-tree.api")
          
          local function opts(desc)
            return { desc = desc, buffer = bufnr, noremap = true, silent = true, nowait = true }
          end
          
          -- デフォルトマッピング
          api.config.mappings.default_on_attach(bufnr)
          
          -- カスタムマッピング
          vim.keymap.set('n', 'l', api.node.open.edit, opts("Open"))
          vim.keymap.set('n', 'h', api.node.navigate.parent_close, opts("Close Directory"))
        end,
      })
      
      -- nvim-tree キーマップ
      vim.keymap.set('n', '<leader>e', '<cmd>NvimTreeToggle<CR>', { silent = true })
      vim.keymap.set('n', '<leader>f', '<cmd>NvimTreeFindFile<CR>', { silent = true })
    end,
  },
}) 