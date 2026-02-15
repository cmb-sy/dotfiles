-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua

local opt = vim.opt

-- Disable unused providers
vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0
vim.g.loaded_python3_provider = 0

----------------------------------------------------------------------
-- UI
----------------------------------------------------------------------
opt.cursorline = true       -- Highlight cursor line
opt.termguicolors = true    -- True color support
opt.signcolumn = "yes"      -- Always show sign column (prevents layout shift)
opt.scrolloff = 8           -- Keep 8 lines visible above/below cursor
opt.sidescrolloff = 8       -- Keep 8 columns visible left/right of cursor

----------------------------------------------------------------------
-- Editing
----------------------------------------------------------------------
opt.wrap = true             -- Wrap long lines (VSCode default)
opt.breakindent = true      -- Indent wrapped lines to match start
opt.linebreak = true        -- Wrap at word boundaries, not mid-word
opt.clipboard = "unnamedplus" -- Use system clipboard

----------------------------------------------------------------------
-- Search
----------------------------------------------------------------------
opt.ignorecase = true       -- Case-insensitive search
opt.smartcase = true        -- ...unless search contains uppercase

----------------------------------------------------------------------
-- Mouse
----------------------------------------------------------------------
opt.mouse = "a"             -- Enable mouse in all modes
opt.mousemodel = "extend"   -- Right-click extends selection (not popup)
