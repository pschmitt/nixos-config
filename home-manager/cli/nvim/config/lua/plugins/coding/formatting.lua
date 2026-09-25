return {
  "stevearc/conform.nvim",
  optional = true,
  opts = {
    formatters_by_ft = {
      ["lua"] = { "stylua" },
      ["python"] = { "isort", "black" },
      ["nix"] = { "nixfmt" },
    },
  },
}
