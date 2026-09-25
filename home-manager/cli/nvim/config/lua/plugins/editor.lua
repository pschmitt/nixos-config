return {
  {
    -- only show relative line number when needed
    -- https://github.com/ericbn/vim-relativize
    "ericbn/vim-relativize",
  },

  {
    -- pick up where you left off
    -- https://github.com/ethanholz/nvim-lastplace
    "ethanholz/nvim-lastplace",
    event = "BufReadPre",
    config = function()
      require("nvim-lastplace").setup({
        lastplace_ignore_buftype = { "quickfix", "nofile", "help" },
        lastplace_ignore_filetype = {
          "gitcommit",
          "gitrebase",
          "svn",
          "hgcommit",
        },
        lastplace_open_folds = true,
      })
    end,
  },

  {
    -- :e myfile:78,8 - line 78 col 8
    -- https://github.com/wsdjeg/vim-fetch
    -- "wsdjeg/vim-fetch",
    "lewis6991/fileline.nvim",
  },
  {
    -- Preemptively jump to line when entering :line_number command (before
    -- hitting <CR>!)(eg: :52)
    -- https://github.com/nacro90/numb.nvim
    "nacro90/numb.nvim",
    event = "BufRead",
    config = function()
      require("numb").setup({
        show_numbers = true, -- Enable 'number' for the window while peeking
        show_cursorline = true, -- Enable 'cursorline' for the window while peeking
      })
    end,
  },

  {
    -- suggest filenames on startup if there's a close match
    -- https://github.com/EinfachToll/DidYouMean
    "EinfachToll/DidYouMean",
  },

  -- Search
  {
    -- %S/address{,es}/reference{,s}/g
    -- https://github.com/tpope/vim-abolish
    "tpope/vim-abolish",
  },
  {
    -- blink search results
    -- https://github.com/ivyl/vim-bling
    "ivyl/vim-bling",
  },
  {
    -- auto disable search hilighting
    -- https://github.com/romainl/vim-cool
    "romainl/vim-cool",
  },

  -- New files
  {
    -- mkdir when trying to write to existent dir
    -- https://github.com/benizi/vim-automkdir
    "benizi/vim-automkdir",
  },
  {
    -- Auto chmod +x new files w/ shebang
    -- https://github.com/tpope/vim-eunuch
    "tpope/vim-eunuch",
  },
}
