-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

vim.opt.wrap = true
vim.opt.spell = true
vim.opt.cursorcolumn = true
vim.opt.termguicolors = true -- required for --headless
vim.opt.list = true

-- Setting statuscolumn to empty string has the effect of having gitsigns
-- placed on the left-most side of the window and not of the right of the
-- line number
vim.opt.statuscolumn = ""

-- Append '-' to the list of keywords (fixes # navigation on shell func names
-- that contain hyphens)
vim.opt.iskeyword:append("-,:")

-- Disable menu transparency (cmp + nvim command line)
vim.opt.pumblend = 0

-- Set local leader to comma
vim.g.maplocalleader = ","

require("config.clipboard")

-- These used to be required from init.lua, which lazyvim-nix generates
require("config.usercmds")
require("config.vimwikisync")
