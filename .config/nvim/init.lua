-- Two jobs: short edits driven from lazygit, and browsing a repo to read what
-- Claude Code just changed. The options below serve the first, the plugins at
-- the bottom serve the second.
--
-- Deliberately does NOT touch expandtab/shiftwidth: files here mix tabs
-- (.function.zsh) and spaces (Lua, YAML), and forcing either would corrupt
-- indentation on save. Whitespace is made visible instead.

-- Must precede lazy.nvim: plugin specs capture the leader when they register
-- their keys, so setting it later leaves those mappings on the old prefix.
vim.g.mapleader = " "
vim.g.maplocalleader = " "

vim.o.number = true      -- line numbers
vim.o.cursorline = true  -- highlight the line the cursor sits on
vim.o.scrolloff = 4      -- keep context visible above and below

-- 24-bit colour. Inheriting the terminal's 16 ANSI colours matched lazygit
-- exactly, but 16 colours cannot separate a type from a function from a
-- string, so everything read as one wall of near-white. Matching the tool next
-- door mattered less than telling code apart.
vim.o.termguicolors = true

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

-- Esc goes back to the tree, treating it as the place you browse from and the
-- file window as somewhere you visit. Also clears the leftover search
-- highlight, which hlsearch otherwise leaves lit with no key to dismiss it.
-- With no tree open it only clears the highlight, so it stays harmless in a
-- lone buffer opened from lazygit. To stay in the file, move with Ctrl-W.
vim.keymap.set("n", "<Esc>", function()
  vim.cmd("nohlsearch")
  if vim.bo.filetype == "neo-tree" then
    return
  end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "neo-tree" then
      vim.api.nvim_set_current_win(win)
      return
    end
  end
end, { desc = "Back to the file tree, clear search highlight" })

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

-- ---------------------------------------------------------------------------
-- Plugins
--
-- lazy.nvim clones itself on first launch, so a fresh machine needs nothing
-- beyond git. Versions are pinned in lazy-lock.json, which is committed.
--
-- Icons are ASCII throughout. The terminal's font is Monaspace Neon with a
-- HackGen fallback, neither of which carries Nerd Font glyphs, so the usual
-- icon sets would render as boxes. To try them anyway, install a Nerd Font as
-- the terminal font and delete the icon overrides below.
-- ---------------------------------------------------------------------------

-- Turns preview on for the tree, and gives it somewhere to draw. Global so the
-- plugin spec's event handler and the window-enter autocmd share one copy.
--
-- Deferred, because a window opened from inside a render is undone by the time
-- it finishes, and preview has to come after the window it draws into exists.
-- Every step reaches into neo-tree's internals, so all of them are guarded: if
-- a later version moves them, the tree still works and `P` still previews by
-- hand.
function _G.neotree_start_preview(state)
  vim.defer_fn(function()
    local ok, preview = pcall(require, "neo-tree.sources.common.preview")
    if not ok or preview.is_active() then
      return
    end
    if vim.bo.filetype ~= "neo-tree" then
      return
    end
    -- `nvim .` hands the tree the only window there is, and preview draws into
    -- a neighbour rather than making one, so it would have nowhere to put the
    -- file under the cursor.
    if #vim.api.nvim_list_wins() == 1 then
      local tree_win = vim.api.nvim_get_current_win()
      vim.cmd("botright vnew")
      pcall(vim.api.nvim_set_current_win, tree_win)
    end
    if not state then
      local ok_m, manager = pcall(require, "neo-tree.sources.manager")
      state = ok_m and manager.get_state("filesystem") or nil
    end
    if not state then
      return
    end
    -- Normally filled in by the keymap dispatcher from the mapping's `config`;
    -- calling toggle directly means supplying it here, and preview reads it
    -- unconditionally.
    state.config = { use_float = false }
    pcall(preview.toggle, state)
  end, 50)
end

vim.api.nvim_create_autocmd("WinEnter", {
  callback = function()
    if vim.bo.filetype == "neo-tree" then
      _G.neotree_start_preview(nil)
    end
  end,
})

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none", "--branch=stable",
    "https://github.com/folke/lazy.nvim.git", lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  {
    -- Colourscheme. Mocha is the flavour Ghostty's theme is built on, so nvim
    -- and the terminal stay in the same family even though Ghostty overrides
    -- part of the palette. Loaded at startup rather than lazily, since every
    -- other highlight is defined against it.
    "catppuccin/nvim",
    name = "catppuccin",
    lazy = false,
    priority = 1000,
    opts = {
      flavour = "mocha",
      -- Ghostty paints a faint circuit pattern behind the terminal; an opaque
      -- editor background would cover it up.
      transparent_background = true,
      styles = { comments = { "italic" }, keywords = { "bold" } },
    },
    config = function(_, opts)
      require("catppuccin").setup(opts)
      vim.cmd.colorscheme("catppuccin")
    end,
  },
  {
    -- Parses the file rather than pattern-matching it, so a function name, a
    -- type and a string get separate colours instead of all landing on
    -- "identifier". This is what actually makes code scannable.
    "nvim-treesitter/nvim-treesitter",
    branch = "master",
    build = ":TSUpdate",
    event = { "BufReadPost", "BufNewFile" },
    opts = {
      -- Only the languages in this repo, installed ahead of time. `auto_install`
      -- is off deliberately: it compiles a parser on first sight of a new
      -- filetype, which stalls the editor at exactly the wrong moment.
      ensure_installed = {
        "lua", "bash", "python", "json", "yaml", "toml", "markdown",
        "markdown_inline", "gitcommit", "diff", "vim", "vimdoc",
      },
      auto_install = false,
      highlight = { enable = true },
      indent = { enable = true },
    },
    config = function(_, opts)
      require("nvim-treesitter.configs").setup(opts)
    end,
  },
  {
    -- Sidebar file tree. Loads on first use rather than at startup, so opening
    -- a commit message from lazygit stays instant.
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = { "nvim-lua/plenary.nvim", "MunifTanjim/nui.nvim" },
    cmd = "Neotree",
    keys = {
      { "<leader>e", "<Cmd>Neotree toggle<CR>", desc = "Toggle file tree" },
    },
    -- Lazy-loading on the command and the key alone means neo-tree is not
    -- loaded yet when nvim starts, so it cannot take netrw's place and
    -- `nvim .` falls through to the old directory listing. Load it eagerly
    -- for that one case: the argument is a directory.
    --
    -- Then lay the window out by hand rather than letting the tree take over
    -- the only window. Preview draws into a neighbouring window and will not
    -- conjure one, so a lone tree has nowhere to show the file under the
    -- cursor. Putting an empty buffer on the right first gives it a target.
    init = function()
      if vim.fn.argc(-1) ~= 1 then
        return
      end
      local stat = (vim.uv or vim.loop).fs_stat(vim.fn.argv(0))
      if not (stat and stat.type == "directory") then
        return
      end
      require("lazy").load({ plugins = { "neo-tree.nvim" } })
    end,
    opts = {
      -- Replaces netrw, so `nvim .` opens the tree instead of the old
      -- directory listing.
      filesystem = {
        hijack_netrw_behavior = "open_default",
        follow_current_file = { enabled = true },
        filtered_items = {
          -- This is a dotfiles repo: hiding dotfiles would hide the point.
          visible = true,
          hide_dotfiles = false,
          hide_gitignored = false,
        },
      },
      window = {
        width = 34,
        mappings = {
          -- Preview into the window on the right rather than a floating box,
          -- so it reads as "the file next to the tree" rather than a popup.
          ["P"] = { "toggle_preview", config = { use_float = false } },
        },
      },

      -- Preview follows the cursor once it is running -- it listens for the
      -- cursor-moved event -- but it starts off, and opening a file with Enter
      -- ends it. Restart it whenever the tree has focus and preview is not
      -- running, so browsing always pages the file beside the tree the way
      -- lazygit does, rather than only until the first file is opened.
      --
      -- Hooked on both events because they cover different moments: the render
      -- is the tree first appearing, the window-enter is coming back to it.
      event_handlers = {
        { event = "after_render", handler = function(state) _G.neotree_start_preview(state) end },
      },
      default_component_configs = {
        icon = {
          folder_closed = "+",
          folder_open = "-",
          folder_empty = "-",
          default = " ",
        },
        git_status = {
          symbols = {
            added = "A", modified = "M", deleted = "D", renamed = "R",
            untracked = "?", ignored = "I", unstaged = "U", staged = "S",
            conflict = "C",
          },
        },
      },
    },
  },
  {
    -- Jumping to a file by name beats walking a tree once a repo is large,
    -- and grep finds the code when only a phrase from it is remembered.
    "nvim-telescope/telescope.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    cmd = "Telescope",
    keys = {
      { "<leader>f", "<Cmd>Telescope find_files<CR>", desc = "Find file by name" },
      { "<leader>g", "<Cmd>Telescope live_grep<CR>",  desc = "Grep in files" },
      { "<leader>b", "<Cmd>Telescope buffers<CR>",    desc = "Open buffers" },
    },
    opts = {
      defaults = {
        -- fd and rg respect .gitignore and skip .git, which keeps the picker
        -- from drowning in build output.
        vimgrep_arguments = {
          "rg", "--color=never", "--no-heading", "--with-filename",
          "--line-number", "--column", "--smart-case",
        },
      },
      pickers = {
        find_files = { find_command = { "fd", "--type", "f", "--hidden", "-E", ".git" } },
      },
    },
  },
}, {
  -- lazy.nvim's own window defaults to Nerd Font glyphs too.
  ui = {
    icons = {
      cmd = "cmd", config = "cfg", event = "ev", ft = "ft", init = "init",
      keys = "keys", plugin = "plug", runtime = "rt", require = "req",
      source = "src", start = "start", task = "task", lazy = "lazy",
    },
  },
  change_detection = { notify = false },
})
