--!nonstrict

local input = noctalia.state.get("mickey_input_state") or { mode = "local" }
local pending = false
local failed = false
local render

local function recall()
  if input.mode ~= "recallable" or pending then
    return
  end

  pending = true
  failed = false
  render()
  local accepted = noctalia.runAsync({ "@mickey@", "home" }, function(result)
    pending = false
    failed = result.exitCode ~= 0 and input.mode == "recallable"
    render()
  end, 3000)
  if not accepted then
    pending = false
    failed = true
    render()
  end
end

render = function()
  if input.mode == "local" then
    desktopWidget.setVisible(false)
    return
  end

  local destination = input.destination and "On " .. input.destination or "On another computer"
  local children = {
    ui.image({ path = "mickey.png", width = 32, height = 32, fit = "contain" }),
    ui.column({ gap = 2, align = "start" }, {
      ui.label({ text = "Input away", fontSize = 12, fontWeight = "semibold", color = "on_surface" }),
      ui.label({
        text = destination,
        fontSize = 10,
        maxWidth = 165,
        maxLines = 1,
        color = "on_surface_variant",
      }),
    }),
  }

  if input.mode == "recallable" then
    table.insert(children, ui.row({
      paddingH = 10,
      paddingV = 7,
      align = "center",
      radius = 11,
      fill = "primary_container",
      onClick = not pending and recall or nil,
    }, {
      ui.label({
        text = if pending then "Bringing back…" elseif failed then "Try again" else "Bring back",
        fontSize = 10,
        fontWeight = "semibold",
        color = "on_primary_container",
      }),
    }))
  end

  desktopWidget.render(ui.row({
    gap = 12,
    align = "center",
    paddingH = 12,
    paddingV = 9,
    radius = 18,
    fill = "surface_container",
    border = "outline_variant",
    borderWidth = 1,
  }, children))
  desktopWidget.setVisible(true)
end

noctalia.state.watch("mickey_input_state", function(value)
  input = value or { mode = "local" }
  if input.mode ~= "recallable" then
    failed = false
  end
  render()
end)

render()

function update()
  render()
end
