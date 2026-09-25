return {
  "vimwiki/vimwiki",
  init = function()
    local documents_dir = vim.env.XDG_DOCUMENTS_DIR or "~/Documents"

    vim.g.vimwiki_list = {
      {
        path = documents_dir .. "/notes",
        syntax = "markdown",
        ext = ".md",
      },
    }
    -- Disable all vimwiki keys
    vim.g.vimwiki_key_mappings = { all_maps = 1 }

    -- Disable concealment of ``` blocks
    -- vim.g.vimwiki_conceallevel = 0
  end,
}
