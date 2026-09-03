--!nonstrict
-- Timewarrior bar widget entry — imperative barWidget.* API (no custom tree
-- needed for a plain icon+text pill). Hidden entirely while nothing is
-- tracked, matching the DMS widget's setVisibilityOverride(false) behavior.

local state = noctalia.state.get("tw_status") or { active = false, duration = "" }

local function isOvertime()
  if not state.active then
    return false
  end
  local hours = tonumber(string.match(state.duration or "", "^(%d+):"))
  local threshold = tonumber(noctalia.getConfig("overtime_hours")) or 7
  return hours ~= nil and hours > threshold
end

local function render()
  barWidget.setVisible(state.active == true)
  if not state.active then
    return
  end

  local overtime = isOvertime()
  local iconColor = noctalia.getConfig("icon_color") or "on_surface"
  local iconOvertimeColor = noctalia.getConfig("icon_overtime_color") or "error"
  local labelColor = noctalia.getConfig("label_color") or "on_surface"
  local labelOvertimeColor = noctalia.getConfig("label_overtime_color") or "error"
  local glyph = noctalia.getConfig("icon_glyph")
  if glyph == nil or glyph == "" then
    glyph = "clock-hour-3"
  end

  barWidget.setGlyph(glyph)
  barWidget.setText(state.duration or "")
  barWidget.setColor(overtime and labelOvertimeColor or labelColor)
  barWidget.setGlyphColor(overtime and iconOvertimeColor or iconColor)
  barWidget.setTooltip("Timewarrior: tracking")
end

noctalia.state.watch("tw_status", function(val)
  if type(val) == "table" then
    state = val
    render()
  end
end)

render()

function update()
  render()
end
