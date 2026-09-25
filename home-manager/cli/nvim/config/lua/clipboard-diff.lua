-- lua/clipboard_diff.lua
local M = {}

local function get_clipboard_lines()
  local clip = vim.fn.getreg('+')
  if clip == nil or clip == '' then
    clip = vim.fn.getreg('*')
  end
  return vim.split(clip or '', '\n', { plain = true })
end

local function set_scratch_opts(buf, ft)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = true
  vim.bo[buf].readonly = false
  vim.bo[buf].filetype = ft or ''
end

local function fill_lines(buf, lines)
  if #lines == 0 then
    lines = { '' }
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

local function map_q_to_close(buf, closer)
  vim.keymap.set('n', 'q', closer, { buffer = buf, nowait = true, silent = true })
end

-- Right-split scratch with lines, return {win, buf}
local function open_right_scratch(name, lines, ft)
  vim.cmd('vsplit')
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, true)
  set_scratch_opts(buf, ft)
  fill_lines(buf, lines)
  -- make name unique to avoid E95
  vim.api.nvim_buf_set_name(buf, string.format('%s #%d', name, buf))
  vim.api.nvim_win_set_buf(win, buf)
  return win, buf
end

local function diff_current_buffer_with_clipboard()
  local clip = get_clipboard_lines()
  if #clip == 1 and clip[1] == '' then
    vim.notify('Clipboard is empty (+ and *).', vim.log.levels.WARN)
    return
  end

  local left_win = vim.api.nvim_get_current_win()
  local ft = vim.bo.filetype
  local right_win, right_buf = open_right_scratch('[Clipboard]', clip, ft)

  -- enable diff both sides
  vim.api.nvim_set_current_win(left_win)
  vim.cmd('diffthis')
  vim.api.nvim_set_current_win(right_win)
  vim.cmd('diffthis')

  -- q closes and cleans up
  local function close_diff_split()
    pcall(vim.api.nvim_command, 'diffoff!')
    pcall(vim.api.nvim_command, 'close')
  end
  map_q_to_close(right_buf, close_diff_split)
  map_q_to_close(vim.api.nvim_get_current_buf(), close_diff_split)
end

local function diff_range_with_clipboard(line1, line2)
  local clip = get_clipboard_lines()
  if #clip == 1 and clip[1] == '' then
    vim.notify('Clipboard is empty (+ and *).', vim.log.levels.WARN)
    return
  end

  local ft = vim.bo.filetype
  local sel = vim.api.nvim_buf_get_lines(0, line1 - 1, line2, false)

  -- new tab with two scratch buffers, uniquely named
  vim.cmd('tabnew')

  -- left scratch
  local left_buf = vim.api.nvim_create_buf(false, true)
  set_scratch_opts(left_buf, ft)
  fill_lines(left_buf, sel)
  vim.api.nvim_buf_set_name(left_buf, string.format('%s #%d', '[Selection]', left_buf))
  vim.api.nvim_win_set_buf(0, left_buf)

  -- right scratch
  vim.cmd('vsplit')
  local right_win = vim.api.nvim_get_current_win()
  local right_buf = vim.api.nvim_create_buf(false, true)
  set_scratch_opts(right_buf, ft)
  fill_lines(right_buf, clip)
  vim.api.nvim_buf_set_name(right_buf, string.format('%s #%d', '[Clipboard]', right_buf))
  vim.api.nvim_win_set_buf(right_win, right_buf)

  -- enable diff
  vim.cmd('wincmd h')
  vim.cmd('diffthis')
  vim.cmd('wincmd l')
  vim.cmd('diffthis')
  vim.cmd('wincmd h')

  -- q closes the tab and diffs
  local function close_tab()
    pcall(vim.api.nvim_command, 'diffoff!')
    pcall(vim.api.nvim_command, 'tabclose')
  end

  map_q_to_close(left_buf, close_tab)
  map_q_to_close(right_buf, close_tab)
end

function M.run(opts)
  if opts.range == 0 then
    diff_current_buffer_with_clipboard()
  else
    diff_range_with_clipboard(opts.line1, opts.line2)
  end
end

function M.setup()
  vim.api.nvim_create_user_command(
    'ClipboardDiff',
    function(opts) M.run(opts) end,
    { range = true, desc = 'Diff current buffer or visual selection with clipboard' }
  )
end

return M
