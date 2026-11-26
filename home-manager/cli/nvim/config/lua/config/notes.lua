-- Notes: vimwiki (+ vimwikisync.lua) and obsidian.nvim on the same vault.
local notes_dir =
  vim.fn.expand((vim.env.XDG_DOCUMENTS_DIR or "~/Documents") .. "/notes")

-- vimwiki reads its globals when it loads, so they are set before plugins
vim.g.vimwiki_list = {
  {
    path = notes_dir,
    syntax = "markdown",
    ext = ".md",
  },
}
-- Disable all vimwiki keys
vim.g.vimwiki_key_mappings = { all_maps = 1 }

-- https://github.com/obsidian-nvim/obsidian.nvim
-- Set up lazily (it costs ~20 ms of every start): on the first vault file or
-- the first :Obsidian command.
if vim.fn.isdirectory(notes_dir) == 1 then
  local function setup_obsidian()
    if vim.g.obsidian_set_up then
      return
    end
    vim.g.obsidian_set_up = true
    pcall(vim.api.nvim_del_user_command, "Obsidian")
    require("obsidian").setup({
      legacy_commands = false, -- this will be removed in the next major release
      frontmatter = {
        -- disable the auto-insertion of header properties
        -- https://help.obsidian.md/Editing+and+formatting/Front+Matter
        enabled = false,
      },
      daily_notes = {
        folder = "daily",
        -- The ID may contain path separators, which nest the note under
        -- daily/<YEAR>/<MONTH>/<date>.md.
        date_format = "%Y/%m/%Y-%m-%d",
      },
      workspaces = {
        {
          name = "notes",
          path = notes_dir,
        },
      },
    })
  end

  vim.api.nvim_create_autocmd({ "BufReadPre", "BufNewFile" }, {
    pattern = notes_dir .. "/*.md",
    once = true,
    callback = setup_obsidian,
  })
  vim.api.nvim_create_user_command("Obsidian", function(opts)
    setup_obsidian()
    vim.cmd("Obsidian " .. opts.args)
  end, { nargs = "*" })
end
