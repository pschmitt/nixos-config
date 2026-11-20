local wezterm = require 'wezterm'
local config = wezterm.config_builder()
local hostname = wezterm.hostname()

config.font = wezterm.font_with_fallback {
  { family = 'ComicCode Nerd Font' },
  { family = "Font Awesome 6 Free" },
  { family = "Font Awesome 5 Free" },
  { family = 'Noto Color Emoji', scale = 1.5 }
}

config.font_size = 15 -- reduce bottom padding of tmux status bar

return config
