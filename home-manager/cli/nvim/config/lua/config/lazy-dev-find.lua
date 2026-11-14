-- lazy.nvim maps a module path back to its plugin by the basename of the
-- plugin directory (lazy.core.plugin.find). lazyvim-nix keeps the dev plugins in
-- "<owner>--<repo>" directories, which never equal the plugin name
-- ("folke--trouble.nvim" vs "trouble.nvim"), so a plugin that is only ever
-- require()d is neither loaded nor added to the runtimepath. For example
-- require("trouble") from the lualine spec then finds the Lua module but not
-- the sources under lua/trouble/sources, and lualine fails with
-- "Failed to run `config` for lualine.nvim" (sources/init.lua: attempt to index
-- local 'source' (a nil value)).
--
-- Fall back to matching the plugin by its directory.

local Plugin = require("lazy.core.plugin")

if Plugin._dev_dir_find then
  return
end

local find = Plugin.find

Plugin._dev_dir_find = true
Plugin.find = function(path, opts)
  local plugin = find(path, opts)
  if plugin then
    return plugin
  end

  local Config = require("lazy.core.config")
  if not Config.spec then
    return
  end

  local lua = path:find("/lua/", 1, true)
  if not lua then
    return
  end
  local dir = path:sub(1, lua - 1)

  local plugins = (opts and opts.fast) and Config.spec.meta.plugins or Config.spec.plugins
  for _, candidate in pairs(plugins) do
    if candidate.dir == dir then
      return candidate
    end
  end
end
