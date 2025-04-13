-- 基本設定
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- 基本オプション
vim.opt.number = true
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.expandtab = true
vim.opt.autoindent = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.hlsearch = true
vim.opt.clipboard = "unnamedplus"
vim.opt.termguicolors = true
vim.opt.mouse = "a"
vim.opt.wrap = false

-- キーマッピング
-- ウィンドウ操作
vim.keymap.set("n", "<leader>w", "<C-w>")
vim.keymap.set("n", "<C-h>", "<C-w>h")
vim.keymap.set("n", "<C-j>", "<C-w>j")
vim.keymap.set("n", "<C-k>", "<C-w>k")
vim.keymap.set("n", "<C-l>", "<C-w>l")

-- ファイル操作
vim.keymap.set("n", "<leader>s", ":w<CR>")
vim.keymap.set("n", "<leader>q", ":q<CR>")
vim.keymap.set("n", "<Esc><Esc>", ":nohl<CR>")

-- バッファ操作
vim.keymap.set("n", "<leader>bn", ":bnext<CR>")
vim.keymap.set("n", "<leader>bp", ":bprevious<CR>")
vim.keymap.set("n", "<leader>bd", ":bdelete<CR>")

-- lazy.nvimのブートストラップ
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