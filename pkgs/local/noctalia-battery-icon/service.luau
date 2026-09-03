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

-- nil until the first status read, so a charger already connected when the
-- service (re)starts doesn't trigger the sound — only an actual plug-in
-- edge does.
local lastCharging = nil
local chargingSoundReady = false

noctalia.sound.load("charging", "sounds/charging.oga", function(ok, err)
  chargingSoundReady = ok
  if not ok then
    noctalia.log("battery-icon: charging sound failed to load: " .. tostring(err))
  end
end)

-- Noctalia's own "color" settings (e.g. bar.color, widget capsule_fill)
-- accept either a hex value or a palette role name like "on_primary" —
-- see docs/user/bar/index.mdx. Its generic color-setting editor offers the
-- same role-name picker here, but a role name means nothing to
-- ImageMagick's -fill, which only understands actual colors. Resolve a
-- role name against the active custom palette file ourselves before it
-- reaches magick.
local paletteCache = { key = nil, colors = nil }

local function roleToPaletteKey(role)
  -- "on_primary" -> "mOnPrimary", matching the palette JSON's Material-ish
  -- key casing (see ~/.config/noctalia/palettes/<name>.json).
  local out = "m"
  for word in role:gmatch("[^_]+") do
    out = out .. word:sub(1, 1):upper() .. word:sub(2)
  end
  return out
end

local function resolveRoleColor(role)
  if noctalia.getSetting("theme.source") ~= "custom" then
    return nil -- built-in palettes aren't user files we can read directly
  end
  local paletteName = noctalia.getSetting("theme.custom_palette")
  if paletteName == nil or paletteName == "" then
    return nil
  end
  local mode = noctalia.isDarkMode() and "dark" or "light"
  local cacheKey = paletteName .. ":" .. mode

  if paletteCache.key ~= cacheKey then
    local raw = noctalia.readFile(noctalia.expandPath("~/.config/noctalia/palettes/" .. paletteName .. ".json"))
    local decoded = raw ~= nil and noctalia.json.decode(raw) or nil
    paletteCache = { key = cacheKey, colors = decoded ~= nil and decoded[mode] or nil }
  end

  if paletteCache.colors == nil then
    return nil
  end
  return paletteCache.colors[roleToPaletteKey(role)]
end

-- `value` is either a hex color or a Noctalia palette role name; `fallback`
-- is the fixed hex used when it's a role name that can't be resolved
-- (built-in palette, unknown role, missing palette file, ...).
local function resolveColor(value, fallback)
  if type(value) ~= "string" or value == "" then
    return fallback
  end
  if value:match("^#%x+$") then
    return value
  end
  return resolveRoleColor(value) or fallback
end

local function settings()
  return {
    device = noctalia.getConfig("battery_device") or "BAT0",
    pollMs = (tonumber(noctalia.getConfig("poll_interval")) or 15) * 1000,
    lowThreshold = tonumber(noctalia.getConfig("low_threshold")) or 20,
    mediumThreshold = tonumber(noctalia.getConfig("medium_threshold")) or 50,
    lowColor = resolveColor(noctalia.getConfig("low_color"), "#FF6B81"),
    mediumColor = resolveColor(noctalia.getConfig("medium_color"), "#F2C94C"),
    highColor = resolveColor(noctalia.getConfig("high_color"), "#6FCF97"),
    chargingColor = resolveColor(noctalia.getConfig("charging_color"), "#B6C4FF"),
    textColor = resolveColor(noctalia.getConfig("text_color"), "#11131A"),
    emptyColor = resolveColor(noctalia.getConfig("empty_color"), "#33333F"),
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
    .. "-"
    .. sanitize(cfg.emptyColor)
    .. ".png"

  if noctalia.fileExists(outPath) then
    noctalia.state.set("battery_icon", { path = outPath, percent = percent, charging = charging })
    return
  end

  -- Fill bar width, clamped so it always shows at least the rounded cap.
  local fillX = math.max(14, 4 + math.floor(104 * math.clamp(percent, 0, 100) / 100))

  -- A proportional-width gauge fill (Android-13-style) made the digits'
  -- optical center shift with the charge level, since the pill's painted
  -- region used to stop at the fill edge — a fixed -annotate offset can't
  -- stay centered when the colored region's own width keeps changing. Fix:
  -- paint the *entire* pill (and knob) with cfg.emptyColor first, so the
  -- shape is always fully covered regardless of charge, then lay the
  -- charge-tier-colored fill on top from the left. Total painted width (and
  -- so the label's true center) is now constant at every percentage.
  --
  -- Canvas is wider than the pill+knob (0-117) so a charging bolt has its
  -- own room on the right and never has to compete with the digits.
  local cmd = "@magick@ -size 144x64 xc:none "
    .. "-fill '"
    .. cfg.emptyColor
    .. "' -draw 'roundrectangle 4,6 108,58 10,10' "
    .. "-draw 'roundrectangle 108,23 117,41 3,3' "
    .. "-fill '"
    .. bg
    .. "' -draw 'roundrectangle 4,6 "
    .. tostring(fillX)
    .. ",58 10,10' "

  if fillX >= 108 then
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

      if lastCharging == false and charging and noctalia.getConfig("charging_sound_enabled") then
        if chargingSoundReady then
          noctalia.sound.play("charging")
        end
      end
      lastCharging = charging

      local key = tostring(percent)
        .. (charging and "c" or "d")
        .. cfg.lowColor
        .. cfg.mediumColor
        .. cfg.highColor
        .. cfg.chargingColor
        .. cfg.textColor
        .. cfg.emptyColor

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
