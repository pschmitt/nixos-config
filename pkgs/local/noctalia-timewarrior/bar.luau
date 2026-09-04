--!nonstrict
-- Timewarrior bar widget entry.
--
-- Declarative render (barWidget.render, not the imperative setGlyph/setText
-- API) so the Timewarrior project logo can sit next to the tracked duration.
-- While nothing is tracked the widget hides by default or, with
-- hide_when_inactive off, keeps its place showing a pause icon.

local duration = require("./lib/duration.luau")

local state = noctalia.state.get("tw_status") or { active = false, duration = "" }

local LOGO_TRACKING = "assets/timewarrior-logo.svg"
local LOGO_STOPPED = "assets/pause.svg"

local function isOvertime()
  if not state.active then
    return false
  end
  local hours = tonumber(string.match(state.duration or "", "^(%d+):"))
  local threshold = tonumber(noctalia.getConfig("overtime_hours")) or 7
  return hours ~= nil and hours > threshold
end

local function icon(active)
  local size = tonumber(noctalia.getConfig("icon_size")) or 16
  return ui.image({
    path = active and LOGO_TRACKING or LOGO_STOPPED,
    width = size,
    height = size,
    fit = "contain",
  })
end

-- Defaults to true, matching the long-standing behaviour of vanishing while
-- nothing is tracked. getConfig returns nil for a setting the user has never
-- touched, which must not read as false.
local function hideWhenInactive()
  local value = noctalia.getConfig("hide_when_inactive")
  if value == nil then
    return true
  end
  return value == true
end

local function render()
  local active = state.active == true
  local container = barWidget.isVertical() and ui.column or ui.row
  local labelColor = noctalia.getConfig("label_color") or "on_surface"

  if not active then
    if hideWhenInactive() then
      barWidget.setVisible(false)
      return
    end
    -- The service publishes duration = "" when the timer is off, so there is
    -- no figure to put beside the icon.
    barWidget.setVisible(true)
    barWidget.render(container({ gap = 5, align = "center" }, { icon(false) }))
    barWidget.setTooltip("Timewarrior: not tracking")
    return
  end

  local overtime = isOvertime()
  local color = overtime and (noctalia.getConfig("label_overtime_color") or "error") or labelColor
  local fmt = noctalia.getConfig("bar_time_format")
  if fmt == nil or fmt == "" then
    fmt = "{hours}:{minutes}"
  end

  barWidget.setVisible(true)
  barWidget.render(container({ gap = 5, align = "center" }, {
    icon(true),
    ui.label({ text = duration.format(state.duration, fmt), color = color }),
  }))
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
