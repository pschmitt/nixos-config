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
  return hours ~= nil and hours > 7
end

local function render()
  barWidget.setVisible(state.active == true)
  if not state.active then
    return
  end

  local overtime = isOvertime()
  barWidget.setGlyph("clock-hour-3")
  barWidget.setText(state.duration or "")
  barWidget.setColor(overtime and "error" or "on_surface")
  barWidget.setGlyphColor(overtime and "error" or "on_surface")
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

function onClick()
  noctalia.togglePanel("pschmitt/timewarrior:panel")
end
