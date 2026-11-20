-- Autocmds, loaded after the plugins are set up (nixvim extraConfigLuaPost)
local function augroup(name)
  return vim.api.nvim_create_augroup("user_" .. name, { clear = true })
end

-- Highlight on yank
vim.api.nvim_create_autocmd("TextYankPost", {
  group = augroup("highlight_yank"),
  callback = function()
    vim.hl.on_yank()
  end,
})

-- Reload files changed outside of nvim
vim.api.nvim_create_autocmd({ "FocusGained", "TermClose", "TermLeave" }, {
  group = augroup("checktime"),
  callback = function()
    if vim.o.buftype ~= "nofile" then
      vim.cmd("checktime")
    end
  end,
})

-- Pick up where you left off
local lastplace_ignored = { gitcommit = true, gitrebase = true, svn = true, hgcommit = true }
vim.api.nvim_create_autocmd("BufReadPost", {
  group = augroup("last_loc"),
  callback = function(event)
    local buf = event.buf
    if
      lastplace_ignored[vim.bo[buf].filetype]
      or vim.bo[buf].buftype ~= ""
      or vim.b[buf].last_loc_done
    then
      return
    end
    vim.b[buf].last_loc_done = true
    local mark = vim.api.nvim_buf_get_mark(buf, '"')
    if mark[1] > 0 and mark[1] <= vim.api.nvim_buf_line_count(buf) then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
      vim.cmd("normal! zv")
    end
  end,
})

-- Create missing parent directories on write
vim.api.nvim_create_autocmd("BufWritePre", {
  group = augroup("auto_create_dir"),
  callback = function(event)
    if event.match:match("^%w%w+:[\\/][\\/]") then
      return
    end
    local file = vim.uv.fs_realpath(event.match) or event.match
    vim.fn.mkdir(vim.fn.fnamemodify(file, ":p:h"), "p")
  end,
})

-- chmod +x new files that start with a shebang
vim.api.nvim_create_autocmd("BufNewFile", {
  group = augroup("shebang_chmod"),
  callback = function(event)
    vim.api.nvim_create_autocmd("BufWritePost", {
      buffer = event.buf,
      once = true,
      callback = function()
        local first = vim.api.nvim_buf_get_lines(event.buf, 0, 1, false)[1] or ""
        if first:match("^#!") then
          vim.fn.system({ "chmod", "+x", vim.api.nvim_buf_get_name(event.buf) })
        end
      end,
    })
  end,
})

-- Close some throwaway windows with q
vim.api.nvim_create_autocmd("FileType", {
  group = augroup("close_with_q"),
  pattern = { "checkhealth", "lspinfo", "notify", "qf", "startuptime" },
  callback = function(event)
    vim.bo[event.buf].buflisted = false
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = event.buf, silent = true })
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
