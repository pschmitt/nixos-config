-- Options, loaded before any plugin is set up (nixvim extraConfigLuaPre).
-- mapleader (space) and maplocalleader (comma) are set by nixvim.

require("config.portable-options")

local opt = vim.opt

-- Former LazyVim defaults we got used to
opt.autowrite = true
opt.completeopt = "menu,menuone,noselect"
opt.confirm = true
opt.cursorline = true
opt.ignorecase = true
opt.smartcase = true
opt.inccommand = "nosplit"
opt.jumpoptions = "view"
opt.laststatus = 3
opt.mouse = "a"
opt.relativenumber = true
opt.scrolloff = 4
opt.sidescrolloff = 8
opt.shiftround = true
opt.showmode = false
opt.signcolumn = "yes"
opt.smartindent = true
opt.splitbelow = true
opt.splitright = true
opt.splitkeep = "screen"
opt.timeoutlen = 300
opt.undofile = true
opt.undolevels = 10000
opt.updatetime = 200
opt.virtualedit = "block"
opt.wildmode = "longest:full,full"
opt.winminwidth = 5
opt.fillchars = { foldopen = "", foldclose = "", fold = " ", foldsep = " ", diff = "╱", eob = " " }

opt.grepprg = "rg --vimgrep"
opt.grepformat = "%f:%l:%c:%m"
opt.linebreak = true
opt.smoothscroll = true
-- Treesitter folds, everything unfolded on open
opt.foldlevel = 99
opt.foldmethod = "expr"
opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
opt.foldtext = ""

local sev = vim.diagnostic.severity
vim.diagnostic.config({
  severity_sort = true,
  underline = true,
  update_in_insert = false,
  virtual_text = { spacing = 4, source = "if_many", prefix = "●" },
  float = { border = "rounded" },
  signs = {
    text = {
      [sev.ERROR] = " ",
      [sev.WARN] = " ",
      [sev.HINT] = " ",
      [sev.INFO] = " ",
    },
  },
})

-- Ours
opt.wrap = true
opt.spell = true
opt.cursorcolumn = true
opt.termguicolors = true -- required for --headless
opt.list = true

-- Append '-' to the list of keywords (fixes # navigation on shell func names
-- that contain hyphens)
opt.iskeyword:append("-,:")

-- Disable menu transparency (completion + nvim command line)
opt.pumblend = 0

require("config.filetypes")
require("config.clipboard")
require("config.usercmds")
require("config.notes")
require("config.vimwikisync")
