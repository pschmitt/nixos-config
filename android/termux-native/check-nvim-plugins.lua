-- Regression check for the Termux Neovim generation: every plugin Lazy resolves
-- must exist in the bundled lazy-dev tree, and Lazy must not have cloned any.
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

local function finish(code, message)
  io.stdout:write(message .. "\n")
  vim.cmd(code == 0 and "qall!" or "cquit " .. code)
end

if #missing > 0 or #cloned > 0 then
  local lines = { ("FAIL: %d of %d plugins unresolved, %d cloned"):format(#missing, total, #cloned) }
  vim.list_extend(lines, vim.tbl_map(function(line)
    return "  missing " .. line
  end, missing))
  vim.list_extend(lines, vim.tbl_map(function(line)
    return "  cloned " .. line
  end, cloned))
  finish(1, table.concat(lines, "\n"))
else
  finish(0, ("PASS: all %d Lazy plugins resolve to bundled sources, none cloned"):format(total))
end
