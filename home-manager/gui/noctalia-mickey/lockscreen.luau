--!nonstrict

local away = noctalia.state.get("mickey_input_away") == true
local pending = false
local failed = false

local function render()
  desktopWidget.render(ui.row({
    gap = 8,
    align = "center",
    padding = 10,
    radius = 14,
    fill = "surface_container",
    visible = away,
    onClick = function()
      if not away or pending then
        return
      end
      pending = true
      failed = false
      render()
      local accepted = noctalia.runAsync({ "@mickey@", "home" }, function(result)
        pending = false
        failed = result.exitCode ~= 0
        render()
      end, 3000)
      if not accepted then
        pending = false
        failed = true
        render()
      end
    end,
  }, away and {
    ui.glyph({ name = "mouse", size = 15, color = "primary" }),
    ui.label({
      text = pending and "Bringing input back…" or (failed and "Try bringing input back again" or "Input away · Bring back"),
      fontSize = 11,
      color = "on_surface",
    }),
  } or {}))
end

noctalia.state.watch("mickey_input_away", function(value)
  away = value == true
  if not away then
    failed = false
  end
  render()
end)

render()

function update()
  render()
end
