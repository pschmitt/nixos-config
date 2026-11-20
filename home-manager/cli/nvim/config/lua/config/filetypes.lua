-- Filetype detection for dotfiles (formerly LazyVim's util.dot extra)
vim.filetype.add({
  extension = { rasi = "rasi", rofi = "rasi", wofi = "rasi" },
  filename = { ["vifmrc"] = "vim" },
  pattern = {
    [".*/waybar/config"] = "jsonc",
    [".*/mako/config"] = "dosini",
    [".*/kitty/.+%.conf"] = "kitty",
    [".*/hypr/.+%.conf"] = "hyprlang",
    ["%.env%.[%w_.-]+"] = "sh",
  },
})
vim.treesitter.language.register("bash", "kitty")
