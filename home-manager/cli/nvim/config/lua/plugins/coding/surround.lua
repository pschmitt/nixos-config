return {
  {
    -- Disabled in favor or nvim-surround
    "nvim-mini/mini.surround",
    enabled = false,
  },
  {
    -- https://github.com/kylechui/nvim-surround
    "kylechui/nvim-surround",
    config = function()
      require("nvim-surround").setup()
    end,
  },
}
