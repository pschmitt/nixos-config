--!nonstrict
-- Battery icon poller — renders a small PNG (rounded pill, charge-tier
-- color, percentage baked into the body) via ImageMagick whenever the
-- charge level, plugged-in state, or relevant settings change,
-- Android-status-bar style.
--
-- The bar-widget ui.* framework (row/column/box/label, all pure flex
-- layout) has no overlay/z-stack primitive, and even Noctalia's own
-- built-in "graphic" battery display mode places its percentage label
-- beside the icon, not on top of it (confirmed against battery_widget.cpp
-- upstream). A live-generated bitmap is the only way to draw the number
-- literally inside the shape instead of next to it.

local function trim(s)
  return noctalia.string.trim(s or "")
end

local function sanitize(s)
  return tostring(s):gsub("[^%w]", "")
end

local lastKey = ""

local function settings()
  return {
    device = noctalia.getConfig("battery_device") or "BAT0",
    pollMs = (tonumber(noctalia.getConfig("poll_interval")) or 15) * 1000,
    lowThreshold = tonumber(noctalia.getConfig("low_threshold")) or 20,
    mediumThreshold = tonumber(noctalia.getConfig("medium_threshold")) or 50,
    lowColor = noctalia.getConfig("low_color") or "#FF6B81",
    mediumColor = noctalia.getConfig("medium_color") or "#F2C94C",
    highColor = noctalia.getConfig("high_color") or "#6FCF97",
    chargingColor = noctalia.getConfig("charging_color") or "#B6C4FF",
    textColor = noctalia.getConfig("text_color") or "#11131A",
  }
end

local function tierColor(cfg, percent, charging)
  if charging then
    return cfg.chargingColor
  end
  if percent <= cfg.lowThreshold then
    return cfg.lowColor
  end
  if percent <= cfg.mediumThreshold then
    return cfg.mediumColor
  end
  return cfg.highColor
end

-- Small Android-style lightning bolt, drawn past the terminal knob (outside
-- the pill+knob shape, in the canvas margin reserved for it below) when
-- charging, so it never competes with the digits for space.
local BOLT_POLYGON = "130,16 125,30 131,30 124,48 130,32 124,32"

-- Track opacity for the un-filled portion of the pill (Android-13+-style
-- charge gauge: a faint full-width track, with a solid fill bar growing
-- left-to-right as the charge level rises), as a hex alpha byte appended to
-- a #RRGGBB color. Only works for plain hex; a role name typed into
-- Settings already fails the same way the rest of this script's colors do.
local function withAlpha(hex, alphaHex)
  if type(hex) == "string" and hex:sub(1, 1) == "#" and #hex == 7 then
    return hex .. alphaHex
  end
  return hex
end

local function regenerate(cfg, percent, charging, dataDir)
  local bg = tierColor(cfg, percent, charging)
  local fg = cfg.textColor
  local label = tostring(percent)
  local outPath = dataDir
    .. "/battery-"
    .. tostring(percent)
    .. (charging and "c" or "d")
    .. "-"
    .. sanitize(bg)
    .. "-"
    .. sanitize(fg)
    .. ".png"

  if noctalia.fileExists(outPath) then
    noctalia.state.set("battery_icon", { path = outPath, percent = percent, charging = charging })
    return
  end

  -- Fill bar width, clamped so it always shows at least the rounded cap.
  local fillX = math.max(14, 4 + math.floor(104 * math.clamp(percent, 0, 100) / 100))
  -- Knob only gets a solid fill once the gauge has actually reached it
  -- (full charge); otherwise it's outline-only, same as the unfilled body,
  -- so the two read as one continuous shape instead of a detached blob.
  local knobFull = fillX >= 108
  local strokeColor = withAlpha(fg, "66")

  -- Canvas is wider than the pill+knob (0-117) so a charging bolt has its
  -- own room on the right and never has to compete with the digits — the
  -- label stays centered on the pill itself via the -annotate offset below,
  -- not on the full canvas.
  local cmd = "@magick@ -size 144x64 xc:none "
    .. "-fill none -stroke '"
    .. strokeColor
    .. "' -strokewidth 3 -draw 'roundrectangle 4,6 108,58 10,10' "
    .. "-draw 'roundrectangle 108,23 117,41 3,3' "
    .. "-stroke none -fill '"
    .. bg
    .. "' -draw 'roundrectangle 4,6 "
    .. tostring(fillX)
    .. ",58 10,10' "

  if knobFull then
    cmd = cmd .. "-fill '" .. bg .. "' -draw 'roundrectangle 108,23 117,41 3,3' "
  end

  cmd = cmd
    .. "-gravity center -fill '"
    .. fg
    .. "' -font '@font@' -pointsize 42 -annotate -11+3 '"
    .. label
    .. "' "

  if charging then
    cmd = cmd
      .. "-fill '"
      .. fg
      .. "' -draw 'polygon "
      .. BOLT_POLYGON
      .. "' "
  end

  cmd = cmd .. "'" .. outPath .. "'"

  noctalia.runAsync(cmd, function(result)
    if result.exitCode == 0 then
      noctalia.state.set("battery_icon", { path = outPath, percent = percent, charging = charging })
    else
      noctalia.log("battery-icon: magick failed: " .. trim(result.stderr))
    end
  end, 5000)
end

local function poll()
  local cfg = settings()
  local capacityPath = "/sys/class/power_supply/" .. cfg.device .. "/capacity"
  local statusPath = "/sys/class/power_supply/" .. cfg.device .. "/status"

  noctalia.runAsync("cat " .. capacityPath, function(capResult)
    local percent = tonumber(trim(capResult.stdout))
    if percent == nil then
      return
    end

    noctalia.runAsync("cat " .. statusPath, function(statusResult)
      local status = trim(statusResult.stdout)
      local charging = status == "Charging" or status == "Full"
      local key = tostring(percent) .. (charging and "c" or "d") .. cfg.lowColor .. cfg.mediumColor .. cfg.highColor .. cfg.chargingColor .. cfg.textColor

      if key == lastKey then
        return
      end
      lastKey = key

      local dataDir = noctalia.pluginDataDir()
      if dataDir ~= nil then
        regenerate(cfg, percent, charging, dataDir)
      end
    end, 5000)
  end, 5000)
end

poll()

function update()
  noctalia.setUpdateInterval(settings().pollMs)
  poll()
end
