return {
  "ibhagwan/fzf-lua",
  opts = function()
    local config = require("fzf-lua.config")

    config.defaults.keymap.fzf["ctrl-l"] = "clear-query"
    config.defaults.keymap.fzf["ctrl-delete"] = "clear-query"

    config.defaults.keymap.builtin["<Esc>"] = "hide"
    -- FIXME Below does not seem to work
    config.defaults.keymap.builtin["<C-BS>"] = "clear-query"
  end,
}
