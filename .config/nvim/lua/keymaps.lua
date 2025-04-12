-- Neovimのキーマップ設定

-- リーダーキーの設定
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- ノーマルモードのマッピング
-- ウィンドウ操作
vim.keymap.set("n", "<leader>w", "<C-w>")
vim.keymap.set("n", "<C-h>", "<C-w>h")
vim.keymap.set("n", "<C-j>", "<C-w>j")
vim.keymap.set("n", "<C-k>", "<C-w>k")
vim.keymap.set("n", "<C-l>", "<C-w>l")

-- ファイル操作
vim.keymap.set("n", "<leader>s", ":w<CR>")
vim.keymap.set("n", "<leader>q", ":q<CR>")

-- 検索ハイライトの消去
vim.keymap.set("n", "<Esc><Esc>", ":nohl<CR>")

-- バッファ操作
vim.keymap.set("n", "<leader>bn", ":bnext<CR>")
vim.keymap.set("n", "<leader>bp", ":bprevious<CR>")
vim.keymap.set("n", "<leader>bd", ":bdelete<CR>") 