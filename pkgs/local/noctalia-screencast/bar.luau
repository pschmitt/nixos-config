--!nonstrict
-- Screencast indicator bar widget — the [[widget]] entry.
--
-- Red dot + "REC" label whenever service.luau reports an active screen
-- share; hidden entirely otherwise (matches the old Waybar module's
-- setVisibilityOverride(false)-when-idle behavior). No click action and no
-- panel: this is a passive indicator, same scope as the widget it replaces.
--
-- The dot breathes (alpha-pulses) while active, like a recording light —
-- driven by our own update() tick, not the service's poll interval, so the
-- animation stays smooth regardless of how often the state file is checked.

local state = noctalia.state.get("screencast_status") or { active = false, apps = {}, output = "" }

-- update() tick while pulsing: fast enough for a smooth breathe, cheap enough
-- (plain ui.box/label re-render, no image generation) to not matter.
local PULSE_FRAME_MS = 100
-- update() tick while idle: state.watch already pushes on/off transitions
-- instantly, so this is just a slow heartbeat, not the change-detection path.
local IDLE_TICK_MS = 5000
-- Floor of the breathing range, so the dot dims but never fully disappears.
local PULSE_MIN_ALPHA = 0.25

local function pulseAlpha()
  local periodMs = math.max(300, tonumber(noctalia.getConfig("pulse_period_ms")) or 1200)
  local phase = (noctalia.nowMs() % periodMs) / periodMs
  -- 0 -> 1 -> 0 across the period, eased at both ends (cosine) instead of a
  -- linear ramp, so the pulse reads as "breathing" rather than a sawtooth.
  local wave = 0.5 - 0.5 * math.cos(phase * 2 * math.pi)
  return PULSE_MIN_ALPHA + (1 - PULSE_MIN_ALPHA) * wave
end

local function tooltip()
  local apps = state.apps or {}
  local text = #apps > 0 and ("Screensharing: " .. table.concat(apps, ", ")) or "Screensharing"
  if state.output and state.output ~= "" then
    text = text .. " (" .. state.output .. ")"
  end
  return text
end

local function render()
  barWidget.setVisible(state.active == true)
  if not state.active then
    return
  end

  local dotColor = noctalia.getConfig("dot_color") or "error"
  local labelColor = noctalia.getConfig("label_color") or "error"
  local dotSize = tonumber(noctalia.getConfig("dot_size")) or 8
  local pulseEnabled = noctalia.getConfig("pulse_enabled") ~= false

  local dotFill = dotColor
  if pulseEnabled then
    dotFill = string.format("%s/%.2f", dotColor, pulseAlpha())
  end

  local container = barWidget.isVertical() and ui.column or ui.row
  barWidget.render(container({ gap = 5, align = "center" }, {
    ui.box({ width = dotSize, height = dotSize, radius = dotSize / 2, fill = dotFill }),
    ui.label({ text = "REC", fontWeight = "bold", color = labelColor }),
  }))
  barWidget.setTooltip(tooltip())
end

-- Switches the update() cadence between the pulse's fast tick and the idle
-- heartbeat. Called both from state.watch (so a transition takes effect on
-- the very next tick instead of waiting out whatever the old interval was)
-- and from update() itself (belt and suspenders, since interval changes take
-- effect starting next tick either way).
local function syncTickRate()
  local pulseEnabled = noctalia.getConfig("pulse_enabled") ~= false
  noctalia.setUpdateInterval(state.active and pulseEnabled and PULSE_FRAME_MS or IDLE_TICK_MS)
end

noctalia.state.watch("screencast_status", function(val)
  if type(val) == "table" then
    state = val
    syncTickRate()
    render()
  end
end)

render()
syncTickRate()

function update()
  syncTickRate()
  render()
end
