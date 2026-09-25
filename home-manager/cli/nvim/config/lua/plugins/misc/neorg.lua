return {
  -- https://github.com/nvim-neorg/neorg
  "nvim-neorg/neorg",
  enabled = false,
  dependencies = { "vhyrro/luarocks.nvim", priority = 1000, config = true },
  config = function()
    local documents_dir = vim.env.XDG_DOCUMENTS_DIR or "~/Documents"

    require("neorg").setup({
      load = {
        ["core.defaults"] = {}, -- Loads default behaviour
        ["core.concealer"] = {}, -- Adds pretty icons to your documents
        ["core.journal"] = { -- Journaling/Diary
          config = {
            strategy = "flat",
            workspace = "notes",
          },
        },
        ["core.dirman"] = { -- Manages Neorg workspaces
          config = {
            workspaces = {
              notes = documents_dir .. "/notes/neorg",
            },
          },
        },
      },
    })
  end,
}
