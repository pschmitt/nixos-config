-- Local, unmanaged config for experimenting (not part of nixos-config):
--   ~/.config/nvim/lua/local/init.lua is loaded last on startup.
-- Extra plugins can be tried from there with vim.pack.add({ "https://..." }).
if vim.uv.fs_stat(vim.fn.expand("~/.config/nvim/lua/local/init.lua")) then
  require("local")
end
