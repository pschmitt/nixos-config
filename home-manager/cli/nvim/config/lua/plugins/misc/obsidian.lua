-- https://github.com/obsidian-nvim/obsidian.nvim
return {
  "obsidian-nvim/obsidian.nvim",
  version = "*", -- recommended, use latest release instead of latest commit
  -- ft = "markdown",
  opts = {
    legacy_commands = false, -- this will be removed in the next major release
    frontmatter = {
      -- disable the auto-insertion of header properties
      -- https://help.obsidian.md/Editing+and+formatting/Front+Matter
      enabled = false,
    },
    daily_notes = {
      -- Optional, if you keep daily notes in a separate directory.
      folder = "daily",
      -- Optional, if you want to change the date format for the ID of daily notes.
      -- The ID may contain path separators, which nest the note under
      -- daily/<YEAR>/<MONTH>/<date>.md.
      date_format = "%Y/%m/%Y-%m-%d",
    },
    workspaces = {
      {
        name = "notes",
        path = (vim.env.XDG_DOCUMENTS_DIR or "~/Documents") .. "/notes",
      },
    },
  },
}
