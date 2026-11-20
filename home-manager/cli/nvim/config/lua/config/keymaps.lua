-- Keymaps, loaded after the plugins are set up (nixvim extraConfigLuaPost)
local map = vim.keymap.set

-- Former LazyVim defaults we got used to
map("n", "<C-h>", "<C-w>h", { desc = "Go to left window" })
map("n", "<C-j>", "<C-w>j", { desc = "Go to lower window" })
map("n", "<C-k>", "<C-w>k", { desc = "Go to upper window" })
map("n", "<C-l>", "<C-w>l", { desc = "Go to right window" })
map("n", "<S-h>", "<cmd>bprevious<cr>", { desc = "Prev buffer" })
map("n", "<S-l>", "<cmd>bnext<cr>", { desc = "Next buffer" })
map({ "i", "n", "s" }, "<esc>", function()
  vim.cmd("noh")
  return "<esc>"
end, { expr = true, desc = "Escape and clear hlsearch" })
map({ "i", "x", "n", "s" }, "<C-s>", "<cmd>w<cr><esc>", { desc = "Save file" })
map("x", "<", "<gv")
map("x", ">", ">gv")

-- Pickers
map("n", "<leader><space>", function() Snacks.picker.smart() end, { desc = "Smart find files" })
map("n", "<leader>/", function() Snacks.picker.grep() end, { desc = "Grep" })
map("n", "<leader>,", function() Snacks.picker.buffers() end, { desc = "Buffers" })
map("n", "<leader>:", function() Snacks.picker.command_history() end, { desc = "Command history" })
map("n", "<leader>ff", function() Snacks.picker.files() end, { desc = "Find files" })
map("n", "<leader>fr", function() Snacks.picker.recent() end, { desc = "Recent files" })
map("n", "<leader>sh", function() Snacks.picker.help() end, { desc = "Help pages" })
map("n", "<leader>sk", function() Snacks.picker.keymaps() end, { desc = "Keymaps" })
map("n", "<leader>sd", function() Snacks.picker.diagnostics() end, { desc = "Diagnostics" })
map("n", "<leader>st", function() Snacks.picker.todo_comments() end, { desc = "Todo comments" })
map("n", "<leader>sR", function() Snacks.picker.resume() end, { desc = "Resume picker" })
map("n", "<leader>n", function() Snacks.notifier.show_history() end, { desc = "Notification history" })

-- LSP (Neovim's own defaults: K, grn, gra, grr, gri, gO, ]d, [d)
map("n", "gd", function() Snacks.picker.lsp_definitions() end, { desc = "Goto definition" })
map("n", "gr", function() Snacks.picker.lsp_references() end, { nowait = true, desc = "References" })
map("n", "gI", function() Snacks.picker.lsp_implementations() end, { desc = "Goto implementation" })
map("n", "gy", function() Snacks.picker.lsp_type_definitions() end, { desc = "Goto type definition" })
map("n", "<leader>ss", function() Snacks.picker.lsp_symbols() end, { desc = "LSP symbols" })
map({ "n", "x" }, "<leader>ca", vim.lsp.buf.code_action, { desc = "Code action" })
map("n", "<leader>cr", vim.lsp.buf.rename, { desc = "Rename" })
map("n", "<leader>cd", vim.diagnostic.open_float, { desc = "Line diagnostics" })

-- Git hunks (gitsigns)
map("n", "]h", function() require("gitsigns").nav_hunk("next") end, { desc = "Next hunk" })
map("n", "[h", function() require("gitsigns").nav_hunk("prev") end, { desc = "Prev hunk" })
map({ "n", "x" }, "<leader>ghs", "<cmd>Gitsigns stage_hunk<cr>", { desc = "Stage hunk" })
map({ "n", "x" }, "<leader>ghr", "<cmd>Gitsigns reset_hunk<cr>", { desc = "Reset hunk" })
map("n", "<leader>ghp", "<cmd>Gitsigns preview_hunk_inline<cr>", { desc = "Preview hunk inline" })
map("n", "<leader>ghb", function() require("gitsigns").blame_line({ full = true }) end, { desc = "Blame line" })

-- Whitespace (trim.nvim)
map("n", "<F8>", "<cmd>Trim<cr>", { silent = true, desc = "Trim whitespace" })
map("n", "<leader>8", "<cmd>Trim<cr>", { silent = true, desc = "Trim whitespace" })

-- Exit and write
vim.keymap.set("n", "<M-Q>", "<cmd>quitall!<cr>", { desc = "Just exit." })
vim.keymap.set("n", "<leader>q", "<cmd>quitall!<cr>", { desc = "Just exit." })
vim.keymap.set("n", "<leader>Q", "<cmd>quitall!<cr>", { desc = "Just exit." })
vim.keymap.set(
  "n",
  "<leader>w",
  "<cmd>lua require('write').write()<CR>",
  { desc = "Write buffer" }
)
vim.keymap.set("n", "<leader>d", ":bdelete<CR>", { desc = "Delete buffer" })
-- vim.keymap.set(
--   "n",
--   "<leader>ww",
--   "<cmd>lua require('write').write()<CR>",
--   { desc = "Write buffer" }
-- )

vim.keymap.set("n", "<leader>p", function()
  vim.cmd('normal! "+p') -- Paste
  vim.cmd("FixNewlines")
end, { desc = "Paste with kitty/ghostty+tmux newlines fix" })

-- the classics
-- jj in insert mode -> Esc (ie. normal mode)
vim.keymap.set("i", "jj", "<Esc>", { desc = "jj -> <Esc>" })

-- buffer navigation
vim.keymap.set(
  "n",
  "<leader>B",
  "<cmd>BufferCycle<CR>",
  { desc = "Switch to alt (or next) buffer" }
)

-- misc
vim.keymap.set(
  "n",
  "<leader>e",
  "<cmd>ReloadCurrentFile<CR>",
  { desc = "Reload current file" }
)
vim.keymap.set(
  "n",
  "<leader>C",
  "<cmd>CdToFileDir<CR>",
  { desc = "cd to current file dir" }
)
-- Map Ctrl-Backspace to delete to beginning of line
-- Ctrl-Backspace to delete "word" (till next space char)
vim.keymap.set(
  "i",
  "<C-BS>",
  [[<C-\><C-O>dB]],
  { desc = "Delete to beginning of line" }
)
vim.keymap.set(
  "i",
  "<C-H>",
  [[<C-\><C-O>dB]],
  { desc = "Delete to beginning of line" }
)

vim.keymap.set(
  "n",
  "<leader>v",
  ":ReplaceWithClipboardContent<cr>",
  { desc = "Replace buffer with clipboard content" }
)

-- lsp
vim.keymap.set("n", "<leader>F", "<cmd>Format<cr>", { desc = "LSP Format" })
vim.keymap.set("n", "<leader>T", function()
  Snacks.picker.diagnostics_buffer()
end, { desc = "Buffer diagnostics" })

-- Windows
vim.keymap.set("n", "<leader>Ww", "<C-W>p", { desc = "Other window" })
vim.keymap.set("n", "<leader>Wd", "<C-W>c", { desc = "Delete window" })
vim.keymap.set(
  "n",
  "<leader>W-",
  "<C-W>s",
  { desc = "Split window vertically" }
)
vim.keymap.set(
  "n",
  "<leader>W|",
  "<C-W>v",
  { desc = "Split window horizontally" }
)

-- Pickers (custom)
vim.keymap.set(
  "n",
  "<C-b>",
  function()
    Snacks.picker.buffers()
  end,
  { desc = "Find buffers" }
)

vim.keymap.set(
  "n",
  "<C-p>",
  "<cmd>GitOrFiles<cr>",
  { desc = "Find files in cwd" }
)
vim.keymap.set(
  "n",
  "<C-g>",
  "<cmd>GitOrYadmFiles<cr>",
  { desc = "Git or YADM Files" }
)
vim.keymap.set(
  "n",
  "<leader>l",
  function()
    Snacks.picker.grep()
  end,
  { desc = "Grep" }
)
vim.keymap.set(
  "n",
  "<leader>y",
  "<cmd>YadmFiles<cr>",
  { desc = "YADM Files" }
)

-- Git
vim.keymap.set(
  "n",
  "<leader><Up>",
  "<cmd>Gitsign prev_hunk<CR>",
  { desc = "Previous Git Hunk" }
)
vim.keymap.set(
  "n",
  "<leader><Down>",
  "<cmd>Gitsign next_hunk<CR>",
  { desc = "Next Git Hunk" }
)
vim.keymap.set(
  "v",
  "gah",
  "<cmd>Gitsigns stage_hunk<cr>",
  { desc = "Git add hunk" }
)
vim.keymap.set(
  "v",
  "guh",
  "<cmd>Gitsigns undo_stage_hunk<cr>",
  { desc = "Git unstage hunk" }
)
vim.keymap.set(
  "v",
  "grh",
  "<cmd>Gitsigns reset_hunk<cr>",
  { desc = "Git reset hunk" }
)
