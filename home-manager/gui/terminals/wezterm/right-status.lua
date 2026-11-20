local wezterm = require 'wezterm'

wezterm.on('update-right-status', function(window, pane)
  -- Each element holds the text for a cell in a "powerline" style << fade
  local cells = {}

  -- Figure out the cwd and host of the current pane.
  -- This will pick up the hostname for the remote host if your
  -- shell is using OSC 7 on the remote host.
  local cwd_uri = pane:get_current_working_dir()
  if cwd_uri then
    local cwd = ''
    local local_hostname = wezterm.hostname()
    local hostname = ''

    if type(cwd_uri) == 'userdata' then
      cwd = string.gsub(cwd_uri.file_path, "/$", "")
      hostname = cwd_uri.host or wezterm.hostname()

      -- Use short form of home directory (~)
      if hostname == local_hostname then
        cwd = string.gsub(cwd, os.getenv('HOME'), '~')
      end
    end

    -- Remove the domain name portion of the hostname
    local dot = hostname:find '[.]'
    if dot then
      hostname = hostname:sub(1, dot - 1)
    end
    if hostname == '' then
      hostname = wezterm.hostname()
    end

    table.insert(cells, cwd)
    table.insert(cells, hostname)
  end

  -- I like my date/time in this style: "Wed Mar 3 08:14"
  -- local date = wezterm.strftime '%H:%M:%S'
  -- table.insert(cells, date)

  -- An entry for each battery (typically 0 or 1 battery)
  -- for _, b in ipairs(wezterm.battery_info()) do
  --   table.insert(cells, string.format('%.0f%%', b.state_of_charge * 100))
  -- end


  -- Colors
  local text_fg = '#1E1E1E'
  local text_bg = '#333333'

  -- The elements to be formatted
  local elements = {}

  -- Translate a cell into elements
  local function push(text, _)
    table.insert(elements, { Foreground = { Color = text_fg } })
    table.insert(elements, { Background = { Color = text_bg } })
    table.insert(elements, { Text = ' ' .. text .. ' ' })
  end

  while #cells > 0 do
    local cell = table.remove(cells, 1)
    push(cell, #cells == 0)
  end

  window:set_right_status(wezterm.format(elements))
end)
