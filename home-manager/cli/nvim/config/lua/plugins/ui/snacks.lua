return {
  {
    "folke/snacks.nvim",
    opts = {
      dashboard = {
        enabled = os.getenv("NO_DASHBOARD") == nil
          and os.getenv("SNACKS_DASHBOARD") ~= nil,
      },
      -- FIXME This seems to just break $ nvim /directory/
      -- -> it just opens a blank buffer
      -- explorer = {
      --   replace_netrw = true,
      -- },
      image = {},
      notifier = {
        timeout = 3000,
        style = "compact", -- compact|minimal|fancy
      },
      picker = {
        sources = {
          explorer = {
            auto_close = true, -- Close explorer when opening a file
          },
        },
        matcher = {
          cwd_bonus = true,
          frecency = true,
          history_bonus = true,
        },
        win = {
          -- input window (search prompt)
          input = {
            keys = {
              -- close the picker on ESC instead of going to normal mode
              ["<Esc>"] = { "close", mode = { "n", "i" } },
            },
          },
        },
      },
      styles = {
        dashboard = {
          -- bo = {
          --   filetype = "dashboard",
          -- },
        },
        notification = {
          wo = { wrap = true }, -- Wrap notifications
        },
      },
    },
  },
}
