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

-- Yanks go to the macOS pasteboard, so a path or snippet can be lifted out of
-- a file and pasted straight into a chat or another app. Note this also means
-- `d` overwrites the clipboard; drop this line if that becomes annoying.
vim.o.clipboard = "unnamedplus"

-- `:q` with unsaved changes prompts to save instead of refusing with
-- "E37: No write since last change", which is a dead end if you do not know
-- `:q!`. Matters most here, where the editor is opened and closed constantly.
vim.o.confirm = true

-- Undo survives closing the file. lazygit opens and quits the editor for every
-- small edit, and without this each quit throws the undo history away. The
-- history lives in ~/.local/state/nvim/undo, never beside the file.
vim.o.undofile = true

-- Clear the leftover search highlight. hlsearch is on by default with no key
-- to dismiss it, so matches stay lit until the next search.
vim.keymap.set("n", "<Esc>", "<Cmd>nohlsearch<CR>", { desc = "Clear search highlight" })

-- Reopen a file at the line you left it on. Skips commit messages, where the
-- cursor belongs at the top on a fresh buffer.
vim.api.nvim_create_autocmd("BufReadPost", {
  callback = function(args)
    if vim.bo[args.buf].filetype == "gitcommit" then
      return
    end
    local mark = vim.api.nvim_buf_get_mark(args.buf, '"')
    if mark[1] > 0 and mark[1] <= vim.api.nvim_buf_line_count(args.buf) then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})
