-- Mickey follows the control socket and emits "off" if it disconnects.
noctalia.state.set("mickey_input_state", "local")
noctalia.state.set("mickey_away_cursor", false)

local away = false
local revision = 0

local function updateCursor()
  revision += 1
  local request = revision
  noctalia.state.set("mickey_away_cursor", false)
  if not away then
    return
  end

  noctalia.runAsync({ "@hyprctl@", "-j", "cursorpos" }, function(result)
    if request ~= revision or result.exitCode ~= 0 then
      return
    end
    local ok, point = pcall(noctalia.json.decode, result.stdout)
    if not ok or type(point) ~= "table" or type(point.x) ~= "number" or type(point.y) ~= "number" then
      return
    end
    for _, output in noctalia.outputs() do
      local x, y = point.x - output.x, point.y - output.y
      if x >= 0 and y >= 0 and x < output.width and y < output.height then
        noctalia.state.set("mickey_away_cursor", { output = output.name, x = x, y = y })
        return
      end
    end
  end, 1000)
end

function onOutputsChanged()
  updateCursor()
end

noctalia.runStream("@mickey@ status --waybar", function(line)
  local ok, status = pcall(noctalia.json.decode, line)
  local state = "local"
  if ok and type(status) == "table" then
    if status.class == "remote" then
      state = "recallable"
    elseif status.class == "local" and status.away == true then
      state = "away"
    end
  end
  noctalia.state.set("mickey_input_state", state)
  local nowAway = ok and type(status) == "table" and status.away == true
  if nowAway ~= away then
    away = nowAway
    updateCursor()
  end
end)
