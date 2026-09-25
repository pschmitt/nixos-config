local M = {}

M.write = function()
  ---@diagnostic disable-next-line: param-type-mismatch
  local has_name = (vim.fn.bufname("%") ~= "")

  if not has_name then
    vim.api.nvim_err_writeln("E32: No file name")
    return
  end

  local filepath = vim.fn.expand("%:p")
  if vim.fn.filewritable(filepath) == 1 then
    -- File is writable, just write
    vim.cmd("write")
    return
  end

  -- File is not writable, try to write with force first, then and only then
  -- escalate to SudaWrite
  -- NOTE this codepath is reached when creating a NEW file (it's not going to
  -- be writable, since it does not exist yet.)
  local success = pcall(vim.api.nvim_command, "write!")
  if not success then
    -- File is not writable, use SudaWrite
    vim.cmd("SudaWrite")
    vim.cmd("edit") -- reload the file
  end
end

return M
