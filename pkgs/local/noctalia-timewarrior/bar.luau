--!nonstrict
-- Timewarrior bar widget entry.
--
-- Declarative render (barWidget.render, not the imperative setGlyph/setText
-- API) so the Timewarrior project logo (assets/timewarrior-logo.svg) can be
-- shown next to the tracked duration — same approach as
-- pkgs/local/noctalia-syncthing/bar.luau's logo. Hidden entirely while
-- nothing is tracked, matching the DMS widget's setVisibilityOverride(false)
-- behavior.

local duration = require("./lib/duration.luau")

local state = noctalia.state.get("tw_status") or { active = false, duration = "" }

local function isOvertime()
  if not state.active then
    return false
  end
  local hours = tonumber(string.match(state.duration or "", "^(%d+):"))
  local threshold = tonumber(noctalia.getConfig("overtime_hours")) or 7
  return hours ~= nil and hours > threshold
end

local function logo()
  local size = tonumber(noctalia.getConfig("icon_size")) or 16
  return ui.image({
    path = "assets/timewarrior-logo.svg",
    width = size,
    height = size,
    fit = "contain",
  })
end

local function render()
  barWidget.setVisible(state.active == true)
  if not state.active then
    return
  end

  local overtime = isOvertime()
  local labelColor = noctalia.getConfig("label_color") or "on_surface"
  local labelOvertimeColor = noctalia.getConfig("label_overtime_color") or "error"
  local fmt = noctalia.getConfig("bar_time_format")
  if fmt == nil or fmt == "" then
    fmt = "{hours}:{minutes}"
  end

  local container = barWidget.isVertical() and ui.column or ui.row
  barWidget.render(container({ gap = 5, align = "center" }, {
    logo(),
    ui.label({
      text = duration.format(state.duration, fmt),
      color = overtime and labelOvertimeColor or labelColor,
    }),
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
