return {
  "folke/persistence.nvim",
  event = "BufReadPre",
  opts = { options = vim.opt.sessionoptions:get() },
  -- stylua: ignore
  keys = {
    -- Disable default keymaps
    { "<leader>qs", mode = { "n" },                                              false },
    { "<leader>ql", mode = { "n" },                                              false },
    { "<leader>qd", mode = { "n" },                                              false },
    { "<leader>Sr", function() require("persistence").load() end,                desc = "Restore Session" },
    { "<leader>Sl", function() require("persistence").load({ last = true }) end, desc = "Restore Last Session" },
    { "<leader>Sd", function() require("persistence").stop() end,                desc = "Don't Save Current Session" },
  },
}
