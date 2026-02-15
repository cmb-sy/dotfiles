-- VSCode-like UI enhancements
return {
  -- Bufferline: VSCode-style tabs at the top
  {
    "akinsho/bufferline.nvim",
    opts = {
      options = {
        mode = "buffers",
        separator_style = "slant",
        show_buffer_close_icons = true,
        show_close_icon = false,
        diagnostics = "nvim_lsp",
        always_show_bufferline = true,
        indicator = { style = "underline" },
        offsets = {
          {
            filetype = "neo-tree",
            text = "Explorer",
            highlight = "Directory",
            separator = true,
          },
        },
      },
    },
  },

  -- Indent guides (VSCode-like indent highlighting)
  {
    "lukas-reineke/indent-blankline.nvim",
    opts = {
      indent = { char = "│" },
      scope = { enabled = true, show_start = true },
    },
  },

  -- Auto-close HTML/JSX tags (essential for web dev)
  {
    "windwp/nvim-ts-autotag",
    event = "InsertEnter",
    opts = {},
  },

  -- TODO/FIXME/HACK highlighting
  {
    "folke/todo-comments.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    opts = {},
  },

  -- Dashboard: VSCode Welcome-like start screen
  {
    "nvimdev/dashboard-nvim",
    event = "VimEnter",
    opts = {
      theme = "hyper",
      config = {
        week_header = { enable = true },
        shortcut = {
          { desc = " Find File", group = "Label", action = "Telescope find_files", key = "f" },
          { desc = " Recent Files", group = "Label", action = "Telescope oldfiles", key = "r" },
          { desc = " Grep Text", group = "Label", action = "Telescope live_grep", key = "g" },
          { desc = " Config", group = "Label", action = "e $MYVIMRC", key = "c" },
          { desc = "󰒲 Lazy", group = "Label", action = "Lazy", key = "l" },
          { desc = " Quit", group = "Label", action = "qa", key = "q" },
        },
      },
    },
    dependencies = { "nvim-tree/nvim-web-devicons" },
  },

  -- Noice: modern command line, messages, and popups
  {
    "folke/noice.nvim",
    opts = {
      presets = {
        bottom_search = true,         -- search bar at bottom
        command_palette = true,        -- command palette style popup
        long_message_to_split = true,  -- long messages go to split
        lsp_doc_border = true,         -- bordered LSP docs
      },
    },
  },

  -- Scrollbar (like VSCode's minimap indicator)
  {
    "petertriho/nvim-scrollbar",
    event = "BufReadPost",
    opts = {
      handle = { blend = 30 },
      marks = {
        Search = { color = "#ff9e64" },
        Error = { color = "#db4b4b" },
        Warn = { color = "#e0af68" },
        Info = { color = "#0db9d7" },
        Hint = { color = "#1abc9c" },
        Misc = { color = "#9d7cd8" },
      },
    },
  },

  -- Smooth scrolling
  {
    "karb94/neoscroll.nvim",
    event = "VeryLazy",
    opts = {
      mappings = { "<C-u>", "<C-d>", "zt", "zz", "zb" },
    },
  },

  -- Which-key timeout: show key hints faster for beginners
  {
    "folke/which-key.nvim",
    opts = {
      delay = 300, -- show hints after 300ms (default 500)
    },
  },
}
