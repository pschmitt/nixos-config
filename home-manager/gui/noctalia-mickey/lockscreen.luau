--!nonstrict

local input = noctalia.state.get("mickey_input_state") or { mode = "local" }
local phase = "idle"
local elapsed = 0
local requestId = 0
local render

local function setPhase(nextPhase)
  phase = nextPhase
  elapsed = 0
  desktopWidget.setNeedsFrameTick(phase == "recalling" or phase == "returned")
  render()
end

local function recall()
  if input.mode ~= "recallable" or phase == "recalling" then
    return
  end

  requestId += 1
  local request = requestId
  setPhase("recalling")
  local accepted = noctalia.runAsync({ "@mickey@", "home" }, function(result)
    if request == requestId and phase == "recalling" and result.exitCode ~= 0 then
      setPhase("failed")
    end
  end, 3000)
  if not accepted then
    setPhase("failed")
  end
end

render = function()
  local returned = phase == "returned"
  if input.mode == "local" and not returned then
    desktopWidget.setVisible(false)
    return
  end

  local pending = phase == "recalling"
  local failed = phase == "failed"
  local fade = if returned then math.clamp((650 - elapsed) / 180, 0, 1) else 1
  local destination = input.destination and "On " .. input.destination or "On another computer"
  local children = {
    ui.image({ path = "mickey.png", width = 32, height = 32, fit = "contain" }),
    ui.column({ gap = 2, align = "start" }, {
      ui.label({
        text = if returned then "Input is back" else "Input away",
        fontSize = 12,
        fontWeight = "semibold",
        color = "on_surface",
      }),
      ui.label({
        text = destination,
        visible = not returned,
        fontSize = 10,
        maxWidth = 165,
        maxLines = 1,
        color = "on_surface_variant",
      }),
    }),
  }

  if returned then
    table.insert(children, ui.glyph({
      name = "check",
      size = 18,
      color = "primary",
      scale = 1 + 0.15 * math.sin(math.pi * math.clamp(elapsed / 220, 0, 1)),
    }))
  elseif input.mode == "recallable" then
    table.insert(children, ui.row({
      paddingH = 10,
      paddingV = 7,
      gap = 6,
      align = "center",
      radius = 11,
      fill = "primary_container",
      onClick = not pending and recall or nil,
    }, {
      ui.glyph({
        name = "arrow-left",
        size = 12,
        color = "on_primary_container",
        translateX = if pending then -2 * (1 - math.cos(elapsed * math.pi / 180)) else 0,
      }),
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
    opacity = fade,
    translateY = 4 * (1 - fade),
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
  if phase == "recalling" and input.mode == "local" then
    setPhase(if input.connected then "returned" else "idle")
  elseif (phase == "returned" and input.mode ~= "local")
      or (phase == "failed" and input.mode ~= "recallable") then
    setPhase("idle")
  else
    render()
  end
end)

function onFrameTick(deltaMs)
  if phase ~= "recalling" and phase ~= "returned" then
    return
  end
  elapsed += tonumber(deltaMs) or 0
  if phase == "returned" and elapsed >= 650 then
    setPhase("idle")
  elseif phase == "recalling" and elapsed >= 3200 then
    setPhase(if input.mode == "recallable" then "failed" else "idle")
  else
    render()
  end
end

render()

function update()
  render()
end
