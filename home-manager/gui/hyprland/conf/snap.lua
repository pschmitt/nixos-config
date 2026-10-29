-- Tile a dragged window on the side of the screen where it is dropped.
local function snap_drop()
  local window = hl.get_active_window()
  local cursor = hl.get_cursor_pos()
  if not window or not window.mapped or not cursor then return end
  local monitor = hl.get_monitor_at(cursor) or hl.get_monitor_at_cursor()
  if not monitor then return end

  local scale = monitor.scale or 1
  local width, height = monitor.width / scale, monitor.height / scale
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
