local ignored_filetypes = {
  "diff",
  "git",
  "gitcommit",
  "unite",
  "qf",
  "help",
  "fugitive",
  -- "markdown",
  "dashboard",
  "snacks_dashboard",
}

return {
  -- Display whitespace characters when in visual mode (↲)
  -- https://github.com/mcauley-penney/visual-whitespace.nvim
  {
    "mcauley-penney/visual-whitespace.nvim",
    opts = {
      excluded = {
        filetypes = ignored_filetypes,
      },
    },
  },

  {
    -- Highlight trailing whitespace
    -- https://github.com/ntpeters/vim-better-whitespace
    "ntpeters/vim-better-whitespace",
    enabled = false, -- conflicts with trim.nvim
    config = function()
      vim.g.better_whitespace_filetypes_blacklist = ignored_filetypes
      vim.g.strip_whitespace_on_save = 1
      vim.g.strip_whitespace_confirm = 1
      vim.g.strip_only_modified_lines = 1
      vim.g.show_spaces_that_precede_tabs = 1

      vim.api.nvim_set_keymap(
        "n",
        "<F8>",
        ":StripWhitespace!<CR>",
        { noremap = true, silent = true }
      )
    end,
    -- FIXME Why doesn't this work?
    -- keys = {
    --   {
    --     "F8",
    --     ":StripWhitespace!<CR>",
    --     mode = { "n" },
    --     desc = "Strip trailing whitespace",
    --   },
    -- },
  },

  {
    -- https://github.com/cappyzawa/trim.nvim
    "cappyzawa/trim.nvim",
    enabled = true, -- conflicts with vim-better-whitespace
    config = function()
      require("trim").setup({
        ft_blocklist = ignored_filetypes,
        trim_on_write = false,
        trim_trailing = true,
        trim_last_line = true,
        trim_first_line = true,
        highlight = true,
        highlight_bg = "#ff0000", -- or 'red'
        highlight_ctermbg = "red",
        notifications = true,
      })

      vim.api.nvim_set_keymap(
        "n",
        "<F8>",
        ":Trim<CR>",
        { noremap = true, silent = true, desc = "Trim whitespace" }
      )
      vim.api.nvim_set_keymap(
        "n",
        "<leader>8",
        ":Trim<CR>",
        { noremap = true, silent = true, desc = "Trim whitespace" }
      )

      vim.api.nvim_create_user_command(
        "WhitespaceHighlightingDisable",
        function()
          -- FIXME Below has no effect whatsoever
          -- require("trim").setup({ highlight = false })
          vim.cmd([[highlight clear ExtraWhitespace]])
        end,
        {}
      )

      vim.api.nvim_create_user_command(
        "WhitespaceHighlightingEnable",
        function()
          require("trim").setup({ highlight = true })
        end,
        {}
      )
    end,
  },
}
