return {
  {
    "nvim-neo-tree/neo-tree.nvim",
    optional = true,
    init = false,
    config = function()
      require("neo-tree").setup({
        sources = {
          "filesystem",
          "buffers",
          "git_status",
          "document_symbols", -- not enabled by default
        },
      })
    end,
    keys = {
      {
        "<F2>",
        function()
          require("neo-tree.command").execute({
            source = "document_symbols",
            toggle = true,
          })
        end,
        desc = "Symbols explorer",
      },
    },
    opts = {
      event_handlers = {
        {
          event = "file_opened",
          handler = function()
            -- auto close
            require("neo-tree.command").execute({ action = "close" })
          end,
        },
      },
    },
  },
}
