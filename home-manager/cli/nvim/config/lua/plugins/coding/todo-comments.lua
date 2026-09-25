return {
  {
    "folke/todo-comments.nvim",
    config = function()
      require("todo-comments").setup({
        keywords = {
          FIXME = {
            icon = " ", -- icon used for the sign, and in search results
            color = "error", -- can be a hex color, or a named color (see below)
          },
          TODO = { icon = " ", color = "info" },
          HACK = { icon = " ", color = "warning", alt = { "DIRTYFIX" } },
          WARN = {
            icon = " ",
            color = "warning",
            alt = { "WARNING", "XXX" },
          },
          PERF = {
            icon = "󰾆 ",
            alt = { "OPTIM", "PERFORMANCE", "OPTIMIZE" },
          },
          NOTE = { icon = " ", color = "hint", alt = { "INFO" } },
        },
        highlight = {
          pattern = [[.*<(KEYWORDS):*\s+]],
        },
      })
    end,
  },
}
