return {
  {
    "lewis6991/gitsigns.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      {
        "purarue/gitsigns-yadm.nvim",
        opts = {
          shell_timeout_ms = 2000,
          disable_inside_gitdir = false,
        },
      },
    },
    opts = {
      -- other configuration for gitsigns...
      current_line_blame = true,
      -- yadm support
      _on_attach_pre = function(bufnr, callback)
        require("gitsigns-yadm").yadm_signs(callback, { bufnr = bufnr })
      end,
    },
  },
}
