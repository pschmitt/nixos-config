-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Remove some default keys
local disabled_keys = {
  -- quit
  "<leader>qq",
  -- yanky.nvim
  "<leader>p",
  -- windows
  "<leader>wd",
  "<leader>wm",
}
for _, key in ipairs(disabled_keys) do
  vim.keymap.del("n", key)
end

-- remap lazyvim's <leader>wm to <leader>Wm
-- LazyVim.ui.maximize():map("<leader>Wm")

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
vim.keymap.set(
  "n",
  "<leader>T",
  "<cmd>Trouble diagnostics toggle<cr>",
  { desc = "TroubleToggle" }
)

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

-- FZF
vim.keymap.set(
  "n",
  "<C-b>",
  function()
    Snacks.picker.buffers()
  end,
  -- "<cmd>FzfLua buffers resume=true<CR>",
  { desc = "Find buffers" }
)

vim.keymap.set(
  "n",
  "<C-p>",
  -- "<cmd>FzfLua files resume=true<cr>",
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
  -- "<cmd>FzfLua grep resume=true<CR>",
  function()
    Snacks.picker.grep()
  end,
  { desc = "Grep" }
)
vim.keymap.set(
  "n",
  "<leader>y",
  "<cmd>YadmFiles<cr>",
  { desc = "Telescope YADM Files" }
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
