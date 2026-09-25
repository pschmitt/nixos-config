-- user commands

vim.api.nvim_create_user_command("ReloadCurrentFile", function()
  -- Change the current directory to the extracted directory
  local bufname = vim.api.nvim_buf_get_name(0)
  vim.cmd("e")
  vim.notify(bufname, vim.log.levels.INFO, {
    id = "buffer-reload",
    title = "File reload",
    icon = "🔃",
  })
end, { nargs = 0 })

vim.api.nvim_create_user_command("CdToFileDir", function()
  -- Get the full path of the current buffer
  local bufname = vim.api.nvim_buf_get_name(0)

  -- Extract the directory part from the full path
  local dir = vim.fn.fnamemodify(bufname, ":p:h")

  -- Change the current directory to the extracted directory
  vim.cmd("cd " .. dir)
  vim.notify(dir, vim.log.levels.INFO, {
    id = "cd",
    title = "Changed directory",
    icon = "📂",
  })
end, { nargs = 0 })

vim.api.nvim_create_user_command("PrintCurrentFilePath", function()
  local filePath = vim.api.nvim_buf_get_name(0)
  print(filePath)
  -- Copy the file path to the system clipboard
  vim.fn.setreg("+", filePath)
end, { nargs = 0 })

vim.api.nvim_create_user_command("Format", function()
  -- Regular, vanilla format command
  -- vim.lsp.buf.format()
  local Util = require("lazyvim.util")
  Util.format({ force = true })
end, { nargs = 0 })

vim.api.nvim_create_user_command("NotificationsHistory", function()
  require("snacks").notifier.show_history()
end, { nargs = 0 })

local function dump(cmd)
  -- Capture the output of the command
  local command_output = vim.fn.execute(cmd)
  if command_output == "" or command_output == nil then
    print(string.format("%s: Empty output", cmd))
    return nil
  end

  -- Open a new empty buffer
  vim.cmd("10split | enew")
  local buffer = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_name(buffer, cmd)

  -- Set buffer options to make it a scratch buffer
  vim.bo[buffer].buftype = "nofile"
  vim.bo[buffer].bufhidden = "wipe"
  vim.bo[buffer].swapfile = false

  -- Split the output into lines and put it into the buffer
  local lines = {}
  local first_non_empty_found = false
  for line in command_output:gmatch("([^\n]*)\n?") do
    -- Remove leading empty lines
    if first_non_empty_found or line ~= "" then
      table.insert(lines, line)
      first_non_empty_found = true
    end
  end

  vim.api.nvim_buf_set_lines(buffer, 0, -1, true, lines)

  -- Set the buffer to read-only
  vim.bo[buffer].modifiable = false

  -- Map <Esc> and q to close the buffer
  local mapped_keys = { "<Esc>", "q" }
  for _, key in ipairs(mapped_keys) do
    vim.api.nvim_buf_set_keymap(
      0,
      "n",
      key,
      ":bd<CR>",
      { noremap = true, silent = true }
    )
  end
end

-- Create the user command
vim.api.nvim_create_user_command("Dump", function(args)
  dump(args.args)
end, { nargs = 1 })

vim.api.nvim_create_user_command("LuaRunCurrentBuffer", function()
  dofile(vim.api.nvim_buf_get_name(0))
end, { desc = "Run the current Lua buffer" })

vim.api.nvim_create_user_command("ReplaceWithClipboardContent", function(opts)
  local line1 = opts.line1
  local line2 = opts.line2
  local clipboard = vim.fn.getreg("+")
  local lines = vim.split(clipboard, "\n", { trimempty = false })

  vim.api.nvim_buf_set_lines(0, line1 - 1, line2, false, lines)
end, {
  range = "%", -- Default to the entire buffer
  desc = "Replace the buffer or the given range with the clipboard contents",
})

vim.api.nvim_create_user_command("YadmFiles", function()
  -- require("fzf-custom").yadm_files()
  require("picker-custom").yadm_files()
end, { nargs = "*", complete = vim.fn.getcwd })

vim.api.nvim_create_user_command("GitOrFiles", function()
  -- require("fzf-custom").git_or_files()
  require("picker-custom").git_or_files()
end, { nargs = "*", complete = vim.fn.getcwd })

vim.api.nvim_create_user_command("GitOrYadmFiles", function()
  -- require("fzf-custom").git_or_yadm_files()
  require("picker-custom").yadm_files()
end, { nargs = "*", complete = vim.fn.getcwd })

-- Below is a workaround for the issue with pasting from the clipboard in
-- a Neovim instance running in kitty/ghostty + tmux
vim.api.nvim_create_user_command("FixNewlines", function()
  -- \x1b1 == 
  vim.cmd([[silent! %s/\%x1b\[27;5;106\~/\r/g]])
end, {})

local function buffer_switch_to_next()
  local buf_cur = vim.fn.bufnr('%')
  local buf_alt = vim.fn.bufnr("#")

  if buf_alt > 0 and buf_alt ~= buf_cur then
    vim.cmd("buffer " .. buf_alt)
  else
    vim.cmd("bnext")
  end
end

vim.api.nvim_create_user_command("BufferCycle", buffer_switch_to_next, {})

require('clipboard-diff').setup()
