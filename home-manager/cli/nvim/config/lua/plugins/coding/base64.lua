return {
  "taybart/b64.nvim",
  keys = {
    {
      "b6d",
      function()
        require("b64").decode()
      end,
      desc = "Base64 decode",
      mode = "v",
    },
    {
      "b6e",
      function()
        require("b64").encode()
      end,
      desc = "Base64 encode",
      mode = "v",
    },
  },
}
