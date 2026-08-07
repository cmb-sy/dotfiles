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
-- ---------------------------------------------------------------------------
-- IME indicator in the ruler
--
-- Neovim cannot see the input method: it sits above the terminal and hands down
-- finished characters, so the editor cannot tell whether the next keystroke will
-- produce "a" or "あ". bin/input-source asks the OS.
--
-- Polled, not watched, because there is no event to subscribe to from inside a
-- terminal. The call costs ~35ms, so it only runs while it can change something:
-- in insert mode, and once when entering or leaving it. Idle cost is zero.
-- ---------------------------------------------------------------------------
local ime = { label = "", busy = false }

local function ime_refresh()
  if ime.busy then return end
  ime.busy = true
  vim.system({ "input-source", "--label" }, { text = true }, function(res)
    ime.busy = false
    local out = (res.stdout or ""):gsub("%s+", "")
    if out ~= "" and out ~= ime.label then
      ime.label = out
      -- The ruler is only repainted on demand; without this the label lags a
      -- keystroke behind the actual state.
      vim.schedule(function() vim.cmd("redrawstatus!") end)
    end
  end)
end

_G.ime_label = function()
  return ime.label
end

-- The timer only runs while inserting, which is the only time the keyboard can
-- change the input source. Gating it this way rather than checking the mode
-- inside the callback also keeps Vimscript out of the timer: a libuv callback
-- runs in a fast event context, where vim.fn.mode() raises E5560.
local ime_timer = vim.uv.new_timer()

vim.api.nvim_create_autocmd("InsertEnter", {
  callback = function()
    ime_refresh()
    ime_timer:start(400, 400, function() vim.schedule(ime_refresh) end)
  end,
  desc = "Poll the IME indicator while inserting",
})

vim.api.nvim_create_autocmd({ "InsertLeave", "VimLeavePre" }, {
  callback = function()
    ime_timer:stop()
    ime_refresh()
  end,
  desc = "Stop polling once out of insert, and catch the state on the way out",
})

vim.api.nvim_create_autocmd("FocusGained", {
  callback = ime_refresh,
  desc = "The source can have changed while another app had focus",
})

-- %= pushes the rest to the right edge; the width is fixed so the ruler does not
-- jump between one-cell "A" and two-cell "あ".
vim.o.ruler = true
vim.o.rulerformat = "%28(%=%{v:lua.ime_label()} %l,%c%V %P%)"
ime_refresh()

-- Cmd+/ toggles the comment on the line or selection. The terminal cannot send
-- Cmd+/, so Ghostty translates it to CSI 21;3~ (alt+F10) -- chosen because herdr
-- forwards F1..F12 chords and drops F13+. Neovim renames a modified function key
-- into the extended range, and that sequence arrives as <F58>: measured, not
-- guessed, because <M-F10> silently matches nothing.
-- gc/gcc are built into Neovim 0.10+, so there is no plugin behind this.
--
-- Two keys, because two paths deliver it. Ghostty's own binding wins once its
-- config is reloaded and sends the chord; until then, and in any terminal
-- speaking the kitty keyboard protocol, Cmd+/ arrives as <D-/> directly. Both
-- names are measured through a pty, and an unmapped <D-/> types itself into the
-- buffer, so leaving it out is visible rather than merely inert.
-- <C-o> runs one normal-mode command and returns to insert, so typing continues
-- where it left off.
for _, key in ipairs({ "<F58>", "<D-/>" }) do
  vim.keymap.set("n", key, "gcc", { remap = true, desc = "Toggle comment (Cmd+/)" })
  vim.keymap.set("x", key, "gc", { remap = true, desc = "Toggle comment (Cmd+/)" })
  vim.keymap.set("i", key, "<C-o>gcc", { remap = true, desc = "Toggle comment (Cmd+/)" })
end

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

-- Declared up here rather than beside the memo code below, because the Esc
-- mapping closes over memo_win and a local declared later is invisible to it.
local memo_path = vim.fn.expand("~/dotfiles/.config/nvim/memo.md")
local memo_win = nil

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
  -- Inside the memo, do nothing further: jumping to the tree would leave the
  -- float open behind it with focus somewhere else. Space closes the memo.
  if memo_win and vim.api.nvim_get_current_win() == memo_win then
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
-- Icons are left at their plugin defaults, which are Nerd Font glyphs.
-- terminal/ghostty/config maps the private-use ranges they live in to FiraCode
-- Nerd Font; without that mapping they would all render as boxes, since
-- neither Monaspace Neon nor HackGen carries those codepoints.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Memo
--
-- A floating scratchpad over whatever is on screen. Toggled rather than
-- opened so the same key puts it away, and saved on close because a
-- scratchpad that asks about unsaved changes is not a scratchpad.
--
-- Kept beside this config and tracked, so it follows to another machine. Note
-- that this repo is public: anything written here is published on push.
-- ---------------------------------------------------------------------------

function _G.toggle_memo()
  if memo_win and vim.api.nvim_win_is_valid(memo_win) then
    local buf = vim.api.nvim_win_get_buf(memo_win)
    if vim.bo[buf].modified then
      vim.api.nvim_win_call(memo_win, function()
        pcall(vim.cmd, "silent write")
      end)
    end
    pcall(vim.api.nvim_win_close, memo_win, false)
    memo_win = nil
    return
  end

  -- Absent on a machine without the vault checked out, so make it rather than
  -- failing.
  if vim.fn.filereadable(memo_path) == 0 then
    vim.fn.mkdir(vim.fn.fnamemodify(memo_path, ":h"), "p")
    vim.fn.writefile({ "# memo", "" }, memo_path)
  end

  local buf = vim.fn.bufadd(memo_path)
  vim.fn.bufload(buf)

  local width = math.min(124, math.floor(vim.o.columns * 0.82))
  local height = math.min(42, math.floor(vim.o.lines * 0.78))
  memo_win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2 - 1),
    col = math.floor((vim.o.columns - width) / 2),
    border = "rounded",
    title = " memo ",
    title_pos = "center",
  })
  vim.wo[memo_win].number = false
  vim.wo[memo_win].signcolumn = "no"
  vim.wo[memo_win].wrap = true

  -- Space is the only way out, so the memo cannot be dismissed by reflex while
  -- reading it. Buffer-local and normal-mode only, so space still types a
  -- space inside the memo. `q` is deliberately not bound: it starts a macro
  -- recording in normal mode, and Esc is handled by the global mapping below.
  vim.keymap.set("n", "<Space>", _G.toggle_memo, { buffer = buf, desc = "Close the memo" })
end

vim.keymap.set("n", "<leader>m", _G.toggle_memo, { desc = "Memo (toggle)" })

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
    --
    -- On the main branch. master is frozen -- last commit 2026-03 -- and inside
    -- that frozen state its python query matched a node ("except*", exception
    -- groups) the pinned python parser did not know, which failed the whole
    -- query and left .py files with no highlighting and a stack trace.
    -- Reinstalling could not fix it: the parser was already at the pinned
    -- revision. main keeps parsers and queries in step.
    --
    -- main is a different plugin: it installs parsers and ships queries, and
    -- nothing else. Highlighting is Neovim's, enabled per filetype below. It
    -- also does not support lazy-loading, hence lazy = false.
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,
    build = ":TSUpdate",
    config = function()
      require("nvim-treesitter").setup()

      -- Only the languages in this repo. Installing is a no-op once they are
      -- present, so this costs nothing on later starts.
      require("nvim-treesitter").install({
        "lua", "bash", "python", "json", "yaml", "toml", "markdown",
        "markdown_inline", "gitcommit", "diff", "vim", "vimdoc",
      })

      -- Highlighting comes from Neovim, not the plugin, and is off until asked
      -- for. Guarded: a filetype whose parser is missing would otherwise throw
      -- on every open.
      vim.api.nvim_create_autocmd("FileType", {
        callback = function(args)
          local lang = vim.treesitter.language.get_lang(args.match)
          if lang and vim.treesitter.language.add(lang) then
            pcall(vim.treesitter.start, args.buf, lang)
          end
        end,
      })
    end,
  },
  {
    -- Sidebar file tree. Loads on first use rather than at startup, so opening
    -- a commit message from lazygit stays instant.
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
      -- File-type icons, coloured per type. Depends on the terminal carrying
      -- Nerd Font glyphs, which terminal/ghostty/config now maps explicitly.
      "nvim-tree/nvim-web-devicons",
    },
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
        width = 38,
        -- Grows when a name would be cut off. The deepest paths here are
        -- claude/agents/implementation-review-*.md, which a fixed width
        -- truncated to the point of being unreadable.
        auto_expand_width = true,
        mappings = {
          -- Preview into the window on the right rather than a floating box,
          -- so it reads as "the file next to the tree" rather than a popup.
          ["P"] = { "toggle_preview", config = { use_float = false } },
          -- Space normally expands a folder here, which Enter already does, so
          -- it is free for the memo. Leaving it on toggle_node would also make
          -- the tree the one place the leader key does not work.
          ["<space>"] = function()
            _G.toggle_memo()
          end,
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
        -- Icons and git symbols left at their defaults, which are Nerd Font
        -- glyphs coloured per file type.
        indent = {
          with_markers = true,
          indent_marker = "│",
          last_indent_marker = "└",
          with_expanders = true,
        },
        git_status = {
          -- Ignored files are dimmed rather than labelled: nearly a third of
          -- this repo is ignored, and a column of "I" was reading as content.
          symbols = { ignored = "" },
        },
      },
    },
  },
  {
    -- Marks changed lines in the sign column, so reading a file shows what
    -- moved without switching to lazygit. The point of this whole setup is
    -- seeing what Claude Code did, and this puts that on the same screen.
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      on_attach = function(buf)
        local gs = require("gitsigns")
        local function map(key, fn, desc)
          vim.keymap.set("n", key, fn, { buffer = buf, desc = desc })
        end
        -- ]c / [c is the long-standing pair for moving between diff hunks.
        map("]c", function() gs.nav_hunk("next") end, "Next changed hunk")
        map("[c", function() gs.nav_hunk("prev") end, "Previous changed hunk")
        map("<leader>hp", gs.preview_hunk, "Preview this hunk")
        map("<leader>hd", gs.diffthis, "Diff this file against HEAD")
      end,
    },
  },
  {
    -- Draws markdown as headings, tables and rules instead of leaving ## and **
    -- as literal characters. Most of what gets read here is markdown -- SKILL.md,
    -- CLAUDE.md, docs -- so this lands on the common case.
    "MeanderingProgrammer/render-markdown.nvim",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    ft = { "markdown" },
    opts = {
      code = { style = "normal" },
    },
  },
  {
    -- Pins the enclosing heading or function to the top line while scrolling,
    -- so a long file does not lose the reader partway down.
    "nvim-treesitter/nvim-treesitter-context",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    event = { "BufReadPost", "BufNewFile" },
    opts = { max_lines = 3, multiline_threshold = 1 },
  },
  {
    -- Every mapping here carries a `desc`, which this turns into a menu: press
    -- the leader and the choices appear, rather than having to remember them.
    -- The recurring question in this setup has been "what can I press", so the
    -- answer lives on the keyboard instead of in a document.
    "folke/which-key.nvim",
    event = "VeryLazy",
    keys = {
      { "<leader>?", function() require("which-key").show({ global = true }) end, desc = "Show every key" },
    },
    opts = {
      preset = "helix",
      -- The helix preset caps the window at 30-60 columns with almost no
      -- padding, which is a hint strip rather than something to read. User opts
      -- are merged after the preset, so these win. Values under 1 are a
      -- fraction of the screen.
      win = {
        width = { min = 58, max = 0.7 },
        height = { min = 14, max = 0.8 },
        padding = { 1, 3 },
        border = "rounded",
        title_pos = "left",
      },
      layout = { width = { min = 46 }, spacing = 4 },
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
