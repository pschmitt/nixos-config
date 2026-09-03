--!nonstrict
-- Battery icon bar widget — displays the pre-rendered PNG from the
-- service (percentage baked directly into the icon body). Left-click opens
-- Control Center's power tab via the manifest's [widget.actions] binding
-- (plugin.toml), not a script callback — that's the only path that anchors
-- the panel under the click instead of centering it on the bar.

local state = noctalia.state.get("battery_icon")

local function render()
  if state == nil or state.path == nil then
    barWidget.setVisible(false)
    return
  end

  local width = tonumber(noctalia.getConfig("icon_width")) or 41
  local height = tonumber(noctalia.getConfig("icon_height")) or 18

  barWidget.setVisible(true)
  barWidget.render(ui.row({}, {
    -- fit="contain": the rendered PNG is 144x64 (2.25:1, wider than the
    -- pill+knob shape itself to leave room for the charging bolt past the
    -- knob) — without contain, a width/height not matching that ratio
    -- stretches and blurs it.
    ui.image({ path = state.path, width = width, height = height, fit = "contain" }),
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
