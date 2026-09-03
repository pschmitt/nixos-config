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
local soundReady = { charging = false, unplug = false }

for _, name in ipairs({ "charging", "unplug" }) do
  noctalia.sound.load(name, "sounds/" .. name .. ".oga", function(ok, err)
    soundReady[name] = ok
    if not ok then
      noctalia.log("battery-icon: " .. name .. " sound failed to load: " .. tostring(err))
    end
  end)
end

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

-- Plug/unplug pulse: the bar has no frame-tick API (setUpdateInterval is
-- the only clock a widget/service gets), so "animation" here means briefly
-- driving that interval fast and rendering a couple of extra blended-color
-- frames before settling on the real icon, instead of a single flat cut.
local ANIM_FRAME_MS = 110
local pendingAnim = nil -- { cfg, percent, charging, dataDir, frames, index }

local function hexToRgb(hex)
  local h = hex:gsub("#", "")
  return tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16)
end

local function blendHex(fromHex, toHex, t)
  local r1, g1, b1 = hexToRgb(fromHex)
  local r2, g2, b2 = hexToRgb(toHex)
  return string.format(
    "#%02X%02X%02X",
    math.clamp(math.round(r1 + (r2 - r1) * t), 0, 255),
    math.clamp(math.round(g1 + (g2 - g1) * t), 0, 255),
    math.clamp(math.round(b1 + (b2 - b1) * t), 0, 255)
  )
end

local function regenerate(cfg, percent, charging, dataDir, bgOverride)
  local bg = bgOverride or tierColor(cfg, percent, charging)
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
    -- fg (textColor) is meant to contrast against the colored pill fill
    -- behind the digits; the bolt sits outside the pill, in the canvas's
    -- transparent margin, which composites onto the bar's own dark
    -- background — a near-black fg bolt there is effectively invisible.
    -- Use bg (the tier/charging color) instead so it reads as a visible
    -- colored accent.
    cmd = cmd
      .. "-fill '"
      .. bg
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

-- Renders the next queued pulse frame, if any, and reports whether the
-- caller should keep ticking fast (true) or fall back to normal poll
-- cadence (false — nothing was pending, or this was the last frame).
-- The blended frames in anim.frames run first; one further call renders
-- the *real* tier color (bgOverride = nil) so the icon actually settles
-- on the true state instead of being left on a blended color forever.
local function advanceAnim()
  if pendingAnim == nil then
    return false
  end
  local anim = pendingAnim
  local bg = anim.index <= #anim.frames and anim.frames[anim.index] or nil
  anim.index += 1
  local finished = anim.index > #anim.frames + 1
  if finished then
    pendingAnim = nil
  end
  regenerate(anim.cfg, anim.percent, anim.charging, anim.dataDir, bg)
  return not finished
end

-- A brief flash toward white, easing back to the real tier color, so a
-- plug/unplug reads as a distinct moment instead of the icon just
-- snapping to its new state.
local function startPulse(cfg, percent, charging, dataDir)
  local target = tierColor(cfg, percent, charging)
  -- blendHex needs exactly #RRGGBB; ImageMagick (and resolveColor) also
  -- accept #RGB/#RGBA/#RRGGBBAA, so skip straight to the real icon rather
  -- than mis-parse a color shorthand into a garbled flash.
  if not target:match("^#%x%x%x%x%x%x$") then
    regenerate(cfg, percent, charging, dataDir)
    return
  end
  local flash = blendHex(target, "#FFFFFF", 0.85)
  pendingAnim = {
    cfg = cfg,
    percent = percent,
    charging = charging,
    dataDir = dataDir,
    frames = { flash, blendHex(target, flash, 0.4) },
    index = 1,
  }
  noctalia.setUpdateInterval(ANIM_FRAME_MS)
  advanceAnim()
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
      -- "Not charging" (distinct from "Discharging") is the kernel
      -- power_supply ABI's status for AC present but the battery not
      -- accepting current — a charge-limit/threshold pause, thermal
      -- protection, etc. It only ever occurs with external power
      -- connected, so treat it as "plugged in" the same as an active
      -- charge, or the icon/sound/pulse never fire once the battery
      -- sits at its charge-limit threshold.
      local charging = status == "Charging" or status == "Full" or status == "Not charging"
      -- nil lastCharging means this is the first read since (re)start: never
      -- an edge, so a charger already connected doesn't fire the sound/pulse.
      local edge = lastCharging ~= nil and lastCharging ~= charging

      if edge and noctalia.getConfig("charging_sound_enabled") then
        if charging and soundReady.charging then
          noctalia.sound.play("charging")
        elseif not charging and soundReady.unplug then
          noctalia.sound.play("unplug")
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
      if dataDir == nil then
        return
      end

      if edge then
        startPulse(cfg, percent, charging, dataDir)
      else
        regenerate(cfg, percent, charging, dataDir)
      end
    end, 5000)
  end, 5000)
end

poll()

-- poll_interval is a fallback safety net; the actual trigger is udev itself
-- -- a plug/unplug fires an immediate "change" event on the power_supply
-- subsystem (both the AC and battery devices), so this reacts right away
-- instead of waiting for the next scheduled poll. One monitor line is
-- enough to re-run poll(); it doesn't matter if a single physical event
-- produces more than one line, poll() is a no-op once the icon is current.
noctalia.runStream("@udevadm@ monitor --udev --subsystem-match=power_supply", function(line)
  poll()
end)

function update()
  -- advanceAnim() returns false both when nothing is pending and right
  -- after it renders the pulse's last (real-color) frame — either way
  -- normal polling should resume.
  if advanceAnim() then
    noctalia.setUpdateInterval(ANIM_FRAME_MS)
    return
  end
  noctalia.setUpdateInterval(settings().pollMs)
  poll()
end
