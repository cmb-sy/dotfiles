-- Readability defaults for short edits: lazygit `e`, git commit messages,
-- quick config tweaks. No plugins, so this works on a fresh machine.
--
-- Deliberately does NOT touch expandtab/shiftwidth: files here mix tabs
-- (.function.zsh) and spaces (Lua, YAML), and forcing either would corrupt
-- indentation on save. Whitespace is made visible instead.

vim.o.number = true      -- line numbers
vim.o.cursorline = true  -- highlight the line the cursor sits on
vim.o.scrolloff = 4      -- keep context visible above and below

-- Render with the terminal's 16 ANSI colours instead of a 24-bit palette of
-- our own, so this matches lazygit and everything else in the terminal.
-- Ghostty overrides the Catppuccin base with a custom palette, so a stock
-- catppuccin plugin for nvim would NOT match; inheriting the terminal does.
-- Cost: coarser highlighting, since there are 16 colours rather than millions.
vim.o.termguicolors = false

-- Show whitespace. Mixed indentation and trailing spaces are invisible
-- otherwise, and they are the usual reason a file "looks wrong".
vim.o.list = true
vim.opt.listchars = { tab = "→ ", trail = "·", nbsp = "␣" }

-- Wrap long lines at word boundaries and keep the indent, rather than
-- cutting mid-word at the screen edge.
vim.o.linebreak = true
vim.o.breakindent = true

-- Case-insensitive search until the pattern contains a capital letter.
vim.o.ignorecase = true
vim.o.smartcase = true
