return {
  "folke/which-key.nvim",
  opts = {
    spec = {
      -- https://github.com/LazyVim/LazyVim/discussions/4062
      -- { "<leader>w", desc = "write" },
      { "<leader>w", proxy = false, hidden = true },
      -- { "<leader>wm", hidden = true, proxy = false },
      { "<leader>q", proxy = false },
      { "<leader>qS", proxy = false, hidden = true },
    },
  },
}
