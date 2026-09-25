-- Dependencies: vimwiki, baleia.nvim

local M = {}

-- Table to store the last sync log
local last_sync_log = { stdout = {}, stderr = {} }

-- Variable to track the current sync job ID
local current_sync_job_id = nil

-- Command for syncing
local sync_cmd = { "zhj", "-c", "vimwiki::sync" }

-- Variable to track if the initial sync has been performed
local initial_sync = false

-- Function to get the Vimwiki directory path
local function get_vimwiki_path()
  local vimwiki_list = vim.g.vimwiki_list
  if not vimwiki_list then
    return nil
  end
  return vim.fn.expand(vimwiki_list[1].path)
end

-- Store Vimwiki path
local vimwiki_path = get_vimwiki_path()

-- Function to check if a file is within the Vimwiki directory
local function is_in_vimwiki_dir(filepath)
  if not vimwiki_path then
    return false
  end

  return filepath:sub(1, #vimwiki_path) == vimwiki_path
end

-- Function to check if the current buffer is within the Vimwiki directory
local function is_vimwiki_buffer()
  if not vimwiki_path then
    return false
  end
  local buf_path = vim.fn.expand("%:p") -- Full path of the current buffer
  return buf_path:sub(1, #vimwiki_path) == vimwiki_path
end

-- Function to reload all Vimwiki buffers
local function reload_vimwiki_buffers()
  if not vimwiki_path then
    return
  end

  -- Iterate over all buffers
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local buf_path = vim.api.nvim_buf_get_name(buf)
      -- Check if the buffer's path starts with the Vimwiki path
      if buf_path:sub(1, #vimwiki_path) == vimwiki_path then
        -- Reload the buffer
        vim.api.nvim_buf_call(buf, function()
          vim.cmd("edit")
        end)
      end
    end
  end
end

-- Function to display the last sync log in a new buffer with colorization
function M.display_last_sync_log()
  if #last_sync_log.stdout == 0 and #last_sync_log.stderr == 0 then
    vim.notify(
      "No sync log available yet.",
      vim.log.levels.WARN,
      { title = "rclone bisync log" }
    )
    return
  end

  -- Create a new buffer and window
  vim.cmd("enew")
  local buf = vim.api.nvim_get_current_buf()

  -- Set buffer options
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  -- metadata
  vim.b[buf].vimwiki_error_log = true

  -- Prepare log content
  local log_content = {
    "=== Standard Output ===",
    unpack(last_sync_log.stdout),
    "",
    "=== Standard Error ===",
    unpack(last_sync_log.stderr),
  }

  -- Apply colorization using baleia.nvim's buf_set_lines
  local baleia = require("baleia").setup({})
  baleia.buf_set_lines(buf, 0, -1, false, log_content)

  -- Set up 'q' to close the buffer
  vim.api.nvim_buf_set_keymap(
    buf,
    "n",
    "q",
    ":bd<CR>",
    { noremap = true, silent = true }
  )

  -- Set up 'r' to remove the lock file and close the buffer if successful
  vim.api.nvim_buf_set_keymap(
    buf,
    "n",
    "r",
    ":VimwikiRemoveSyncLock<CR>",
    { noremap = true, silent = true }
  )
end

-- Function to find and close Vimwiki error log buffers
function M.close_vimwiki_error_log_buffers()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if
      vim.api.nvim_buf_is_loaded(buf)
      and vim.bo[buf].buftype == "nofile"
      and vim.b[buf].vimwiki_error_log
    then
      vim.cmd("bwipeout " .. buf)
    end
  end
end

-- Function to check if sync failed due to lock
local function did_sync_fail_due_to_lock()
  local lock_error_pattern = "prior lock file found:"
  for _, line in ipairs(last_sync_log.stderr) do
    if line:find(lock_error_pattern) then
      return true, line
    end
  end
  return false, nil
end

-- Function to run the sync command asynchronously
function M.run_sync_command(is_initial)
  -- Skip if the initial sync has already been performed
  if is_initial and initial_sync then
    return
  end

  local filepath = vim.fn.expand("%:p") -- Full path of the current file
  if not is_in_vimwiki_dir(filepath) then
    return
  end

  -- Prevent starting a new sync job if one is already running
  if
    current_sync_job_id
    and vim.fn.jobwait({ current_sync_job_id }, 0)[1] == -1
  then
    vim.notify(
      "A sync operation is already in progress.",
      vim.log.levels.WARN,
      { id = "rclone-bisync-already-in-progress", title = "Sync Operation" }
    )
    return
  end

  -- Clear previous logs
  last_sync_log.stdout = {}
  last_sync_log.stderr = {}

  vim.notify(
    (is_initial and "Initial sync starting..." or "Sync starting..."),
    vim.log.levels.INFO,
    { id = "rclone-bisync", title = "rclone bisync" }
  )

  current_sync_job_id = vim.fn.jobstart(sync_cmd, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if data then
        vim.list_extend(last_sync_log.stdout, data)
      end
    end,
    on_stderr = function(_, data)
      if data then
        vim.list_extend(last_sync_log.stderr, data)
      end
    end,
    on_exit = function(_, code)
      if code == 0 then
        vim.notify("Sync succeeded", vim.log.levels.INFO, {
          id = "rclone-bisync",
          title = "rclone bisync",
          icon = "✅",
        })
        reload_vimwiki_buffers()
      else
        local lock_failed = did_sync_fail_due_to_lock()
        if lock_failed then
          vim.notify(
            "The sync operation failed because the repo is locked. Please run :VimwikiRemoveSyncLock",
            vim.log.levels.ERROR,
            { id = "rclone-bisync", title = "rclone bisync" }
          )
        else
          vim.notify(
            "Sync failed with rc "
              .. code
              .. ". Check the log for more details (:VimwikiLastSyncLog)",
            vim.log.levels.ERROR,
            { id = "rclone-bisync", title = "rclone bisync" }
          )
        end
        M.display_last_sync_log()
      end
      -- Clear the current job ID upon completion
      current_sync_job_id = nil
    end,
  })

  -- Check if the job was successfully started
  if current_sync_job_id <= 0 then
    vim.notify(
      "Failed to start the shell command."
        .. "\nPlease check if "
        .. table.concat(sync_cmd, " ")
        .. " is a thing",
      vim.log.levels.ERROR,
      { title = "Shell Command Error" }
    )
    current_sync_job_id = nil
  else
    -- Mark the initial sync as completed if applicable
    if is_initial then
      initial_sync = true
    end
  end
end

-- Function to run the sync command asynchronously on exit
local function run_sync_on_exit()
  -- Start the job asynchronously
  vim.fn.jobstart(sync_cmd, {
    -- No need to handle stdout/stderr or exit callbacks
    -- as Neovim will be exiting
    detach = true, -- Detach the process so it continues after Neovim exits
  })
end

-- Function to strip ANSI escape codes from a string
local function strip_ansi_codes(text)
  return text:gsub("\27%[%d+m", "") -- Remove ANSI escape sequences
end

-- Function to extract the lock file path from the sync log and delete it
function M.remove_sync_lock()
  local lock_failed, lock_line = did_sync_fail_due_to_lock()
  if not lock_failed or not lock_line then
    vim.notify(
      "No lock file path found in the sync log.",
      vim.log.levels.WARN,
      { title = "Remove Sync Lock" }
    )
    return
  end

  local lock_file_path = lock_line:match("prior lock file found: *([^\n]+) *")
  if lock_file_path then
    lock_file_path = strip_ansi_codes(lock_file_path) -- Clean the path
    -- trim whitespace
    lock_file_path = lock_file_path:gsub("^%s+", ""):gsub("%s+$", "")
  end

  -- If no lock file path is found, notify the user and return
  if not lock_file_path then
    vim.notify(
      "No lock file path found in the sync log.",
      vim.log.levels.WARN,
      { title = "Remove Sync Lock" }
    )
    return
  end

  -- Execute the rclone deletefile command
  local cmd = { "rclone", "delete", lock_file_path }
  local result = vim.fn.system(cmd)

  -- Clean the result output
  local clean_result = strip_ansi_codes(result)

  -- Check for errors
  if vim.v.shell_error == 0 then
    vim.notify(
      "Lock file successfully removed: " .. lock_file_path,
      vim.log.levels.INFO,
      { title = "Remove Sync Lock" }
    )
    M.close_vimwiki_error_log_buffers()
    -- Sync again
    M.run_sync_command(false)
  else
    vim.notify(
      "Failed to remove lock file: " .. lock_file_path .. "\n" .. clean_result,
      vim.log.levels.ERROR,
      { title = "Remove Sync Lock" }
    )
  end
end

-- Create a user command to remove the sync lock file
vim.api.nvim_create_user_command(
  "VimwikiRemoveSyncLock",
  M.remove_sync_lock,
  {}
)

-- Create a user command to display the last sync log
vim.api.nvim_create_user_command(
  "VimwikiLastSyncLog",
  M.display_last_sync_log,
  {}
)

vim.api.nvim_create_user_command("VimwikiSync", function()
  M.run_sync_command(false)
end, {})

local is_termux = require("utils").is_termux()

if is_termux and os.getenv("VIMWIKI_NO_SYNC") == nil then
  -- Autocommand to trigger sync on buffer write
  vim.api.nvim_create_autocmd("BufWritePost", {
    -- pattern = "*.md",
    callback = function()
      if is_vimwiki_buffer() then
        M.run_sync_command(false)
      end
    end,
  })

  -- Autocommand to trigger initial sync only once when a Vimwiki buffer is opened
  vim.api.nvim_create_autocmd("BufEnter", {
    callback = function()
      if is_vimwiki_buffer() then
        M.run_sync_command(true)
      end
    end,
  })
  -- Autocommand to trigger sync on VimLeavePre
  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      if is_vimwiki_buffer() then
        run_sync_on_exit()
      end
    end,
  })

end

-- register keys to reload/show logs/remove lock
vim.api.nvim_create_autocmd("FileType", {
  pattern = "vimwiki",
  callback = function()
    vim.api.nvim_buf_set_keymap(
      vim.api.nvim_get_current_buf(),
      "n",
      "<localleader>s",
      ":VimwikiSync<CR>",
      { noremap = true, silent = true }
    )
    vim.api.nvim_buf_set_keymap(
      vim.api.nvim_get_current_buf(),
      "n",
      "<localleader>l",
      ":VimwikiLastSyncLog<CR>",
      { noremap = true, silent = true }
    )
    vim.api.nvim_buf_set_keymap(
      vim.api.nvim_get_current_buf(),
      "n",
      "<localleader>r",
      ":VimwikiRemoveSyncLock<CR>",
      { noremap = true, silent = true }
    )
  end,
})
