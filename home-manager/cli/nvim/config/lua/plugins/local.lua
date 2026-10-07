-- Local, unmanaged config for experimenting (not part of nixos-config):
--   ~/.config/nvim/lua/local/init.lua       is loaded on startup
--   ~/.config/nvim/lua/local/plugins/*.lua  are imported as plugin specs
local config_dir = vim.fn.stdpath("config")
if vim.env.TERMUX_GENERATION then
  config_dir = vim.fn.expand("~/.config/nvim")
end
local dir = config_dir .. "/lua/local"

if vim.uv.fs_stat(dir .. "/init.lua") then
  require("local")
end

if vim.fn.glob(dir .. "/plugins/*.lua") ~= "" then
  return { import = "local.plugins" }
end

return {}
