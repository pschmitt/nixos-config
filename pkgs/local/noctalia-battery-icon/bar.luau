--!nonstrict
-- Battery icon bar widget — displays the pre-rendered PNG from the
-- service (percentage baked directly into the icon body). Left-click opens
-- Control Center's power tab, matching the built-in "battery" widget's
-- default gesture (see widget_gesture_defaults.cpp upstream: kBattery =
-- {Gesture::Left, "panel-toggle control-center power"}). ui.image has no
-- onClick of its own, so it's wrapped in a row.

local state = noctalia.state.get("battery_icon")

local function openPowerPanel()
  noctalia.runAsync("noctalia msg panel-toggle control-center power")
end

local function render()
  if state == nil or state.path == nil then
    barWidget.setVisible(false)
    return
  end

  barWidget.setVisible(true)
  barWidget.render(ui.row({ onClick = openPowerPanel }, {
    ui.image({ path = state.path, width = 36, height = 18 }),
  }))
  barWidget.setTooltip(tostring(state.percent) .. "%" .. (state.charging and " (charging)" or ""))
end

noctalia.state.watch("battery_icon", function(val)
  state = val
  render()
end)

render()

function update()
  render()
end
