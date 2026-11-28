--!nonstrict

local state = noctalia.state.get("mickey_input_state") or "local"
local pending = false
local failed = false

local function render()
  local away = state ~= "local"
  local recallable = state == "recallable"
  desktopWidget.render(ui.row({
    gap = 8,
    align = "center",
    padding = 10,
    radius = 14,
    fill = "surface_container",
    visible = away,
    onClick = recallable and function()
      if state ~= "recallable" or pending then
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
    end or nil,
  }, away and {
    ui.label({
      text = if not recallable then "Input away"
        elseif pending then "Bringing input back…"
        elseif failed then "Try bringing input back again"
        else "Input away · Bring back",
      fontSize = 11,
      color = "on_surface",
    }),
  } or {}))
end

noctalia.state.watch("mickey_input_state", function(value)
  state = value or "local"
  if state ~= "recallable" then
    failed = false
  end
  render()
end)

render()

function update()
  render()
end
