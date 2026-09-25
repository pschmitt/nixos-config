-- Make q or Esc close help windows
vim.cmd("nmap <buffer> <silent>q :close<cr>") -- this is already set in lunarvim
vim.cmd("nmap <buffer> <silent><Esc> :close<cr>")
-- Enter to follow links, backspace to get back to previous topic
vim.cmd("nnoremap <buffer> <CR> <C-]>")
vim.cmd("nnoremap <buffer> <BS> <C-T>")
