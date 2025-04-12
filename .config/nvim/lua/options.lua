-- Neovimの基本オプション設定

-- 行番号表示
vim.opt.number = true

-- タブとインデント設定
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.expandtab = true
vim.opt.autoindent = true

-- 検索設定
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.hlsearch = true

-- クリップボード設定
vim.opt.clipboard = "unnamedplus"

-- その他の設定
vim.opt.termguicolors = true
vim.opt.mouse = "a"
vim.opt.wrap = false 