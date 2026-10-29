-- Tile a dragged window on the side of the screen where it is dropped.
local function snap_target(window, cursor)
  if not window or not window.mapped or not cursor then return end
  local monitor = hl.get_monitor_at(cursor) or hl.get_monitor_at_cursor()
  if not monitor then return end

  -- monitor.width/height are the panel's native pixels; rotated outputs
  -- (odd transform) swap them in the logical layout space.
  local scale = monitor.scale or 1
  local width, height = monitor.width / scale, monitor.height / scale
  if (monitor.transform or 0) % 2 == 1 then width, height = height, width end
  local x, y = (cursor.x - monitor.x) / width, (cursor.y - monitor.y) / height
  local left, right = x < 0.05, x > 0.95
  local top, bottom = y < 0.05, y > 0.95
  if not (left or right or top or bottom) then return end

  local target = "address:" .. window.address
  local has_tiled = false
  for _, other in ipairs(hl.get_workspace_windows(window.workspace)) do
    if other.address ~= window.address and other.mapped and not other.floating then
      has_tiled = true
      break
    end
  end
  local reserved = monitor.reserved or {}
  local ax = monitor.x + (reserved.left or 0)
  local ay = monitor.y + (reserved.top or 0)
  local aw = width - (reserved.left or 0) - (reserved.right or 0)
  local ah = height - (reserved.top or 0) - (reserved.bottom or 0)
  -- A side edge takes precedence at a corner; the result is always tiled.
  local side = left and "left" or right and "right" or top and "top" or "bottom"
  return { window = window, target = target, monitor = monitor, has_tiled = has_tiled,
    ax = ax, ay = ay, aw = aw, ah = ah, side = side }
end

local function snap_drop()
  local result = snap_target(hl.get_active_window(), hl.get_cursor_pos())
  if not result then return end
  local window, target, has_tiled = result.window, result.target, result.has_tiled
  local ax, ay, aw, ah, side = result.ax, result.ay, result.aw, result.ah, result.side
  hl.timer(function()
    if window.pinned then
      hl.dispatch(hl.dsp.window.pin({ window = target, action = "off" }))
    end
    if window.floating then
      hl.dispatch(hl.dsp.window.float({ action = "off", window = target }))
    end
    if not has_tiled then return end

    hl.dispatch(hl.dsp.focus({ window = target }))
    hl.dispatch(hl.dsp.layout("movetoroot"))
    local current = hl.get_window(target)
    if not current then return end
    local horizontal = side == "left" or side == "right"
    if (current.size.x < aw * 0.75) ~= horizontal then
      hl.dispatch(hl.dsp.layout("togglesplit"))
      current = hl.get_window(target)
      if not current then return end
    end
    local wrong_side = (side == "left" and current.at.x > ax + aw / 2)
      or (side == "right" and current.at.x < ax + aw / 2)
      or (side == "top" and current.at.y > ay + ah / 2)
      or (side == "bottom" and current.at.y < ay + ah / 2)
    if wrong_side then hl.dispatch(hl.dsp.layout("swapsplit")) end
  end, { timeout = 20, type = "oneshot" })
end

hl.bind("SUPER + mouse:272", snap_drop, { drag = true, transparent = true, description = "Snap window to screen edge" })

-- Write only when the target changes. The runtime directory is a local tmpfs;
-- the preview process never intercepts pointer or keyboard input.
local preview_path = os.getenv("XDG_RUNTIME_DIR") .. "/hypr-snap-preview.json"
local last_preview
local function publish_preview(value)
  if value == last_preview then return end
  local file = io.open(preview_path, "w")
  if file then
    file:write(value)
    file:close()
    last_preview = value
  end
end
local start_cursor
local drag_window
local preview_timer = hl.timer(function()
  local cursor = hl.get_cursor_pos()
  if not cursor or not drag_window or not drag_window.mapped then
    publish_preview("{}")
    return
  end
  local dx, dy = cursor.x - start_cursor.x, cursor.y - start_cursor.y
  local result = dx * dx + dy * dy >= 100 and snap_target(drag_window, cursor)
  if not result then
    publish_preview("{}")
    return
  end
  local x = result.ax - result.monitor.x
  local y = result.ay - result.monitor.y
  local w, h = result.aw, result.ah
  if result.has_tiled then
    if result.side == "left" or result.side == "right" then
      w = w / 2
      if result.side == "right" then x = x + w end
    else
      h = h / 2
      if result.side == "bottom" then y = y + h end
    end
  end
  publish_preview(string.format('{"monitor":%q,"x":%d,"y":%d,"width":%d,"height":%d}',
    result.monitor.name, math.floor(x), math.floor(y), math.floor(w), math.floor(h)))
end, { timeout = 40, type = "repeat" })
preview_timer:set_enabled(false)
publish_preview("{}")

hl.bind("SUPER + mouse:272", function()
  drag_window = hl.get_active_window()
  start_cursor = hl.get_cursor_pos()
  if drag_window and start_cursor then preview_timer:set_enabled(true) end
end, { transparent = true })

hl.bind("SUPER + mouse:272", function()
  preview_timer:set_enabled(false)
  drag_window = nil
  publish_preview("{}")
end, { release = true, transparent = true, ignore_mods = true })

hl.on("config.unload", function()
  preview_timer:set_enabled(false)
  publish_preview("{}")
end)
