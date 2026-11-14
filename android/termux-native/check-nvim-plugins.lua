-- Regression check for the Termux Neovim generation: every plugin Lazy resolves
-- must exist in the bundled lazy-dev tree, Lazy must not have cloned any, a
-- require() of a not yet loaded plugin must map back to that plugin (so Lazy
-- loads it), and the lualine trouble statusline must build.
--
-- Run it with the generation's own launcher so the managed config is used:
--   TERMUX_GENERATION=... XDG_CONFIG_HOME=$TERMUX_GENERATION/home/.config \
--     nvim --headless "+luafile $TERMUX_GENERATION/shell/check-nvim-plugins.lua"
-- It prints one summary line and exits non-zero on any problem.
local uv = vim.uv or vim.loop
local Config = require("lazy.core.config")

local missing = {}
local total = 0
for name, plugin in pairs(Config.plugins) do
  total = total + 1
  if not uv.fs_stat(plugin.dir) then
    table.insert(missing, ("%s -> %s"):format(name, plugin.dir))
  end
end
table.sort(missing)

-- install.missing = false: nothing may have been cloned into Lazy's data root.
local cloned = {}
local root = Config.options.root
if uv.fs_stat(root) then
  for entry in vim.fs.dir(root) do
    table.insert(cloned, entry)
  end
end

-- lazy.core.plugin.find must map "<dev dir>/lua/..." back to the plugin even
-- though the dev dirs are named "<owner>--<repo>"; otherwise a require()d lazy
-- plugin (trouble.nvim) is not loaded and lualine's config fails.
local Plugin = require("lazy.core.plugin")
local unmapped = {}
for name, plugin in pairs(Config.plugins) do
  local found = Plugin.find(plugin.dir .. "/lua/x.lua")
  if not found or found.dir ~= plugin.dir then
    table.insert(unmapped, name)
  end
end
table.sort(unmapped)

-- The statusline lualine builds from LazyVim's ui spec (the actual startup
-- error was "Failed to run `config` for lualine.nvim").
local statusline_error
if Config.plugins["trouble.nvim"] and Config.plugins["lualine.nvim"] then
  local ok, err = pcall(function()
    return require("trouble").statusline({ mode = "symbols", groups = {}, title = false })
  end)
  if not ok then
    statusline_error = tostring(err)
  end
end

local function finish(code, message)
  io.stdout:write(message .. "\n")
  vim.cmd(code == 0 and "qall!" or "cquit " .. code)
end

if #missing > 0 or #cloned > 0 or #unmapped > 0 or statusline_error then
  local lines = {
    ("FAIL: %d of %d plugins unresolved, %d cloned, %d not mapped by require"):format(
      #missing,
      total,
      #cloned,
      #unmapped
    ),
  }
  if statusline_error then
    table.insert(lines, "  trouble statusline: " .. statusline_error)
  end
  vim.list_extend(lines, vim.tbl_map(function(name)
    return "  unmapped " .. name
  end, unmapped))
  vim.list_extend(lines, vim.tbl_map(function(line)
    return "  missing " .. line
  end, missing))
  vim.list_extend(lines, vim.tbl_map(function(line)
    return "  cloned " .. line
  end, cloned))
  finish(1, table.concat(lines, "\n"))
else
  finish(0, ("PASS: all %d Lazy plugins resolve to bundled sources, none cloned, require() loads them"):format(total))
end
