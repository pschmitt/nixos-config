local wezterm = require 'wezterm'
local config = wezterm.config_builder()

config.use_fancy_tab_bar = false
config.hide_tab_bar_if_only_one_tab = true

config.tab_max_width = 20
config.tab_bar_at_bottom = true

-- This function returns the suggested title for a tab.
-- It prefers the title that was set via `tab:set_title()`
-- or `wezterm cli set-tab-title`, but falls back to the
-- title of the active pane in that tab.
local function tab_title(tab, max_width)
  local title = tab.tab_title
  -- if the tab title is explicitly set, take that
  if not title or #title == 0 then
    title = tab.active_pane.title
  end
  -- pad with spaces
  return ' ' .. string.sub(title, 1, max_width - 2) .. ' '
end

wezterm.on(
  'format-tab-title',
  function(tab, tabs, panes, config, hover, max_width)
    local title = tab_title(tab, max_width)
    if tab.is_active then
      return {
        { Background = { Color = 'black' } },
        { Text = title },
      }
    end
    return title
  end
)

return config
