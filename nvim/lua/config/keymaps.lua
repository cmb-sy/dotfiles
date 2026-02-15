-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
--
-- VSCode-like keybindings for a familiar editing experience

local map = vim.keymap.set

----------------------------------------------------------------------
-- File operations
----------------------------------------------------------------------
map({ "n", "i", "v" }, "<C-s>", "<cmd>w<cr><esc>", { desc = "Save file" })

----------------------------------------------------------------------
-- Undo / Redo
----------------------------------------------------------------------
map("n", "<C-z>", "u", { desc = "Undo" })
map("i", "<C-z>", "<C-o>u", { desc = "Undo" })
map("n", "<C-S-z>", "<C-r>", { desc = "Redo" })
map("i", "<C-S-z>", "<C-o><C-r>", { desc = "Redo" })

----------------------------------------------------------------------
-- Selection
----------------------------------------------------------------------
map("n", "<C-a>", "ggVG", { desc = "Select all" })
map("i", "<C-a>", "<Esc>ggVG", { desc = "Select all" })

----------------------------------------------------------------------
-- Clipboard (visual mode)
----------------------------------------------------------------------
map("v", "<C-c>", '"+y', { desc = "Copy" })
map("v", "<C-x>", '"+d', { desc = "Cut" })

----------------------------------------------------------------------
-- Comment toggle (Ctrl+/)
----------------------------------------------------------------------
map("n", "<C-/>", "gcc", { remap = true, desc = "Toggle comment" })
map("v", "<C-/>", "gc", { remap = true, desc = "Toggle comment" })

----------------------------------------------------------------------
-- Search / Navigation
----------------------------------------------------------------------
-- File finder
map("n", "<C-p>", "<cmd>Telescope find_files<cr>", { desc = "Find files" })
-- Command palette
map("n", "<C-S-p>", "<cmd>Telescope commands<cr>", { desc = "Command palette" })
-- Grep across project
map("n", "<C-S-f>", "<cmd>Telescope live_grep<cr>", { desc = "Search in project" })
-- Find in file
map("n", "<C-f>", "/", { desc = "Search in file" })

----------------------------------------------------------------------
-- UI Toggles
----------------------------------------------------------------------
-- Sidebar (file explorer)
map("n", "<C-b>", "<cmd>Neotree toggle<cr>", { desc = "Toggle file explorer" })
-- Terminal (LazyVim uses Snacks.terminal)
map("n", "<C-`>", function() Snacks.terminal() end, { desc = "Toggle terminal" })
map("t", "<C-`>", "<cmd>close<cr>", { desc = "Hide terminal" })

----------------------------------------------------------------------
-- Line manipulation
----------------------------------------------------------------------
-- Move lines with Alt+Arrow (Alt+j/k is already set by LazyVim)
map("n", "<A-Up>", "<cmd>m .-2<cr>==", { desc = "Move line up" })
map("n", "<A-Down>", "<cmd>m .+1<cr>==", { desc = "Move line down" })
map("i", "<A-Up>", "<Esc><cmd>m .-2<cr>==gi", { desc = "Move line up" })
map("i", "<A-Down>", "<Esc><cmd>m .+1<cr>==gi", { desc = "Move line down" })
map("v", "<A-Up>", ":m '<-2<cr>gv=gv", { desc = "Move selection up" })
map("v", "<A-Down>", ":m '>+1<cr>gv=gv", { desc = "Move selection down" })

-- Duplicate line (Ctrl+Shift+D)
map("n", "<C-S-d>", "<cmd>t.<cr>", { desc = "Duplicate line" })
map("v", "<C-S-d>", "y'>p", { desc = "Duplicate selection" })

----------------------------------------------------------------------
-- Buffer navigation (tab-like)
----------------------------------------------------------------------
map("n", "<C-Tab>", "<cmd>bnext<cr>", { desc = "Next buffer" })
map("n", "<C-S-Tab>", "<cmd>bprevious<cr>", { desc = "Previous buffer" })
-- Close buffer: use <leader>bd (LazyVim default) instead of Ctrl+W
-- to avoid breaking Neovim's window management prefix
