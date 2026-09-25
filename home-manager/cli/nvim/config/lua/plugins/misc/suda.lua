return {
  -- write as root
  -- https://github.com/lambdalisue/suda.vim
  "lambdalisue/suda.vim",
  cmd = { "SudaWrite" },
  init = function()
    vim.api.nvim_command("command! Sw SudaWrite %")
    vim.api.nvim_command("cnoremap w!! SudaWrite %")
  end,
}
