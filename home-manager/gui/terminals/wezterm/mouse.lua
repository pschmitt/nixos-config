local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- FIXME The cursor theme is cursed
config.xcursor_theme = 'Bibata-Modern-Ice'
config.xcursor_size = 24
-- config.default_cursor_style = 'BlinkingBlock'
config.hide_mouse_cursor_when_typing = false
config.mouse_bindings = {
  -- FIXME WIP Attempt to scroll less fast on wayland
  {
    event = { Down = { streak = 1, button = { WheelUp = 1 } } },
    mods = 'NONE',
    action = wezterm.action.ScrollByLine(-1),
    alt_screen = false,
  },
  {
    event = { Down = { streak = 1, button = { WheelDown = 1 } } },
    mods = 'NONE',
    action = wezterm.action.ScrollByLine(1),
    alt_screen = false,
  },

  -- Also paste when SHIFT is held (default in tmux)
  {
    event = { Up = { streak = 1, button = 'Middle' } },
    mods = 'SHIFT',
    action = wezterm.action.PasteFrom 'PrimarySelection'
  },
}

return config
