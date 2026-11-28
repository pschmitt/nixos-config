local outputName = noctalia.getConfig("output")
local point = noctalia.state.get("mickey_away_cursor")

local function render()
  local output
  for _, candidate in noctalia.outputs() do
    if candidate.name == outputName then
      output = candidate
      break
    end
  end
  if type(point) ~= "table" or point.output ~= outputName or not output then
    desktopWidget.setVisible(false)
    return
  end

  local scale = math.max(0.01, noctalia.getSetting("accessibility.ui_scale") or 1)
  local width, height, gap = 28, 19, 8
  local x = if point.x > output.width - width - 12
    then math.max(0, point.x - width - gap) else point.x + 12
  local y = if point.y >= height + gap
    then point.y - height - gap else math.min(output.height - height, point.y + gap)

  -- Fill the lock surface with a passive layout and offset the badge inside
  -- it. No node handles pointer events, so the login and recall UI stay usable.
  desktopWidget.render(ui.column({
    minWidth = output.width / scale,
    minHeight = output.height / scale,
    gap = 0,
    align = "start",
    justify = "start",
  }, {
    ui.row({ minHeight = y / scale }),
    ui.row({ gap = 0, align = "start" }, {
      ui.row({ minWidth = x / scale }),
      ui.row({
        minWidth = width / scale,
        minHeight = height / scale,
        fill = "#262239",
        border = "#baa3e8",
        borderWidth = 1 / scale,
        radius = height / (2 * scale),
        align = "center",
        justify = "center",
      }, {
        ui.label({ text = "zZ", fontSize = 11 / scale, fontWeight = "bold", color = "#f1e6ff" }),
      }),
    }),
  }))
  desktopWidget.setVisible(true)
end

noctalia.state.watch("mickey_away_cursor", function(value)
  point = value
  render()
end)

render()

function update()
  render()
end
