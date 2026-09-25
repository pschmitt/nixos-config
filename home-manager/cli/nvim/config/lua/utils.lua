local M = {}

function M.is_termux()
  return vim.fn.executable("termux-info") == 1
end

local function parse_os_release()
  -- cached data? -> return it
  if vim.g.os_release_data then
    return vim.g.os_release_data
  end

  local os_release_file = "/etc/os-release"
  if not vim.loop.fs_stat(os_release_file) then
    return nil
  end

  local lines = vim.fn.readfile(os_release_file)
  local data = {}
  for _, line in ipairs(lines) do
    local key, value = line:match("^(%w+)%=(.+)$")
    if key and value then
      -- Remove surrounding quotes if present
      value = value:gsub('^"(.-)"$', "%1")
      data[key] = value
    end
  end

  -- Cache the entire data table globally
  vim.g.os_release_data = data

  return data
end

function M.os_release_id()
  local os_data = parse_os_release()
  return os_data and os_data.ID or nil
end

function M.is_os(value)
  local os_id = M.os_release_id()
  return os_id and os_id:lower() == value:lower()
end

function M.is_nixos()
  return M.is_os("nixos")
end

function M.is_fedora()
  return M.is_os("fedora")
end

function M.is_ubuntu()
  return M.is_os("ubuntu")
end

function M.has_openai_key()
  return os.getenv("OPENAI_API_KEY") ~= nil
end

function M.remove_element(t, value)
  for i, v in pairs(t) do
    -- NOTE i would be a number if t is a regular table
    -- eg: t = { "foo", "bar", "baz" }
    if type(i) == "number" then
      if v == value then
        table.remove(t, i)
      end
    elseif i == value then
      -- NOTE here i is a key inside the table
      -- eg: t = { "foo": { "bar": "baz" } }
      -- We can't do table.remove here since i would need be a number
      t[i] = nil
    end
  end

  return t
end

function M.in_git_repo()
  local git_dir = vim.fn.system("git rev-parse --is-inside-work-tree 2>/dev/null")
  return vim.v.shell_error == 0 and git_dir:match("true")
end

return M
