-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
-- Add any additional autocmds here

-- disable autoformatting for all filetypes
vim.api.nvim_create_autocmd({ "FileType" }, {
  pattern = { "*" },
  callback = function()
    vim.b.autoformat = false
  end,
})

vim.api.nvim_create_autocmd("BufWinEnter", {
  pattern = "*.envrc",
  command = "set filetype=sh",
})

vim.api.nvim_create_autocmd("BufWinEnter", {
  pattern = "*.ipy",
  command = "set filetype=python",
})

-- Disable diagnostics for markdown buffers
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "markdown", "markdown.mdx" },
  callback = function()
    vim.diagnostic.enable(false, { bufnr = vim.api.nvim_get_current_buf() })
  end,
})

-- FZF dashboard
-- vim.api.nvim_create_autocmd({ "VimEnter" }, {
--   callback = function()
--     if vim.fn.argc(-1) == 1 then
--       local fn = vim.fn.argv(0)
--       ---@diagnostic disable-next-line: param-type-mismatch
--       local stat = vim.loop.fs_stat(fn)
--       if stat and stat.type == "directory" then
--         -- Custom user command, see usercmds.lua
--         -- vim.cmd(string.format(":TelescopeFindFilesOrQuit %s/", fn))
--         vim.cmd(":FzfLua files resume=true")
--       end
--     end
--   end,
-- })
