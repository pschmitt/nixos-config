return {
  {
    "folke/noice.nvim",
    enabled = true,
    opts = {
      cmdline = {
        enabled = true,
        -- Disable the weird cmdline popup that shows up on top.
        -- Use a classic cmdline at the bottom
        view = "cmdline",
      },
    },
  },

  -- Color scheme
  {
    "navarasu/onedark.nvim",
    config = function()
      require("onedark").setup({
        style = "darker",
        code_style = {
          comments = "none",
        },
      })
      require("onedark").load()
    end,
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "onedark",
    },
  },

  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    opts = function()
      return {
        sections = {
          lualine_a = { "mode" },
          lualine_b = { "branch", "diff", "diagnostics" },
          lualine_c = { "filename" },
          lualine_x = { "filetype" },
          lualine_y = {},
          lualine_z = { "location" },
        },
        options = {
          component_separators = { left = "", right = "" },
          section_separators = { left = "", right = "" },
        },
      }
    end,
  },
}
