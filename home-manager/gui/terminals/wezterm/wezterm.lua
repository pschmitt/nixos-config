local wezterm = require 'wezterm'
local helpers = require 'helpers'

local config = wezterm.config_builder()

-- We are running the HEAD/nightly version of Wezterm
config.check_for_updates = false

-- Set TERM (requires the terminfo!)
config.term = "wezterm"

-- Theming
if os.getenv('SCRATCHPAD') == "1" then
  config.color_scheme = 'Wild Cherry (Gogh)'
else
  config.color_scheme = 'Whimsy'
end

-- https://wezfurlong.org/wezterm/config/lua/config/unicode_version.html
config.unicode_version = 14

-- fonts
local fonts = require 'fonts'
helpers.mergeDictTables(config, fonts)

-- mouse
local mouse = require 'mouse'
helpers.mergeDictTables(config, mouse)

-- chrome
-- config.window_decorations = "INTEGRATED_BUTTONS|RESIZE"
config.enable_wayland = true
config.window_padding = {
  left = 0,
  right = 0,
  top = 0,
  bottom = 0
}

-- tab bar
local tabs = require 'tabs'
helpers.mergeDictTables(config, tabs)

require 'right-status'

return config
