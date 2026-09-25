return {
  {
    -- Show breadcrumbs on the top
    -- https://github.com/utilyre/barbecue.nvim
    "utilyre/barbecue.nvim",
    dependencies = {
      "SmiteshP/nvim-navic",
      "nvim-tree/nvim-web-devicons",
    },
    config = function()
      require("barbecue").setup({})
    end,
  },
}
