--!nonstrict
-- Battery icon poller — renders a small Material 3 Expressive-style PNG
-- (clipped charge level and percentage inside the battery body, plus a
-- terminal or charging bolt) via ImageMagick whenever the charge level,
-- power state, or relevant settings change.
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
    lowColor = resolveColor(noctalia.getConfig("low_color"), "#EA4335"),
    mediumColor = resolveColor(noctalia.getConfig("medium_color"), "#9AA0A6"),
    highColor = resolveColor(noctalia.getConfig("high_color"), "#9AA0A6"),
    chargingColor = resolveColor(noctalia.getConfig("charging_color"), "#34A853"),
    chargingBoltColor = resolveColor(noctalia.getConfig("charging_bolt_color"), "#FFFFFF"),
    powerSaverColor = resolveColor(noctalia.getConfig("power_saver_color"), "#FBBC04"),
    textColor = resolveColor(noctalia.getConfig("text_color"), "#202124"),
    emptyColor = resolveColor(noctalia.getConfig("empty_color"), "#F1F3F4"),
  }
end

local function tierColor(cfg, percent, charging, powerSaver)
  if charging then
    return cfg.chargingColor
  end
  if powerSaver then
    return cfg.powerSaverColor
  end
  if percent <= cfg.lowThreshold then
    return cfg.lowColor
  end
  if percent <= cfg.mediumThreshold then
    return cfg.mediumColor
  end
  return cfg.highColor
end

-- Geometry follows the linked Android Material 3 Expressive reference.
-- The body is deliberately much shorter than the full canvas: unplugged
-- batteries get a small terminal on the right, while charging replaces it
-- with the larger external bolt. BODY_PATH also gives the left end slightly
-- rounder corners than the right, as in Android's 24x14 source geometry.
local BODY_PATH = "M4,21 C4,12.716 8.925,6 15,6 H81 C85.971,6 90,11.373 90,18 V46 C90,52.627 85.971,58 81,58 H15 C8.925,58 4,51.284 4,43 Z"
local TERMINAL = "94,21 101,43 3,3"

-- Adapted from AOSP's Apache-2.0 battery_unified_attr_charging vector,
-- scaled and moved just past the battery body.
-- Keeping it external means the number stays centered and legible instead
-- of being squeezed to one side at the bar's 18 px display height.
local BOLT_POLYGON = "96,56 99,39 86,39 109,8 114,8 111,27 126,27 101,56"
local BOLT_STROKE_WIDTH = 3.5

-- Plug/unplug pulse: the bar has no frame-tick API (setUpdateInterval is
-- the only clock a widget/service gets), so "animation" here means briefly
-- driving that interval fast and rendering a couple of extra blended-color
-- frames before settling on the real icon, instead of a single flat cut.
local ANIM_FRAME_MS = 110
local pendingAnim = nil -- { cfg, percent, charging, powerSaver, dataDir, frames, index }

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

local function regenerate(cfg, percent, charging, powerSaver, dataDir, bgOverride)
  local bg = bgOverride or tierColor(cfg, percent, charging, powerSaver)
  local fg = cfg.textColor
  local label = tostring(percent)
  local outPath = dataDir
    .. "/battery-m3e-v5-"
    .. tostring(percent)
    .. (charging and "c" or "d")
    .. (powerSaver and "s" or "n")
    .. "-"
    .. sanitize(bg)
    .. "-"
    .. sanitize(fg)
    .. "-"
    .. sanitize(cfg.emptyColor)
    .. "-"
    .. sanitize(cfg.chargingBoltColor)
    .. ".png"

  if noctalia.fileExists(outPath) then
    noctalia.state.set(
      "battery_icon",
      { path = outPath, percent = percent, charging = charging, powerSaver = powerSaver }
    )
    return
  end

  -- Paint the empty body, then composite a rectangular level fill through
  -- a body-shaped mask. This produces Android's straight vertical level
  -- boundary while retaining the body's rounded outer edge; drawing a
  -- second rounded rectangle here gives the fill a visibly incorrect
  -- rounded boundary at 20% and 50%.
  local fillX = 4 + math.floor(86 * math.clamp(percent, 0, 100) / 100)
  local cmd = "@magick@ -size 128x64 xc:none "
    .. "-fill '"
    .. cfg.emptyColor
    .. "' -draw 'path \""
    .. BODY_PATH
    .. "\"' "
    .. "\\( -size 128x64 xc:none -fill '"
    .. bg
    .. "' -draw 'rectangle 4,6 "
    .. tostring(fillX)
    .. ",58' "
    .. "\\( -size 128x64 xc:none -fill white -draw 'path \""
    .. BODY_PATH
    .. "\"' \\) -compose DstIn -composite \\) -compose Over -composite "

  if charging then
    cmd = cmd
      .. "-fill '"
      .. cfg.chargingBoltColor
      .. "' -stroke '"
      .. fg
      .. "' -strokewidth "
      .. tostring(BOLT_STROKE_WIDTH)
      .. " -draw 'polygon "
      .. BOLT_POLYGON
      .. "' "
  else
    cmd = cmd .. "-fill '" .. cfg.emptyColor .. "' -draw 'roundrectangle " .. TERMINAL .. "' "
  end

  -- The full canvas includes the terminal/bolt area, so -17 places the
  -- text at x=47: the exact horizontal center of the 4..90 body.
  cmd = cmd
    .. "-gravity center -fill '"
    .. fg
    .. "' -stroke none -font '@font@' -pointsize 48 -annotate -17+2 '"
    .. label
    .. "' "

  cmd = cmd .. "'" .. outPath .. "'"

  noctalia.runAsync(cmd, function(result)
    if result.exitCode == 0 then
      noctalia.state.set(
        "battery_icon",
        { path = outPath, percent = percent, charging = charging, powerSaver = powerSaver }
      )
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
  regenerate(anim.cfg, anim.percent, anim.charging, anim.powerSaver, anim.dataDir, bg)
  return not finished
end

-- A brief flash toward white, easing back to the real tier color, so a
-- plug/unplug reads as a distinct moment instead of the icon just
-- snapping to its new state.
local function startPulse(cfg, percent, charging, powerSaver, dataDir)
  local target = tierColor(cfg, percent, charging, powerSaver)
  -- blendHex needs exactly #RRGGBB; ImageMagick (and resolveColor) also
  -- accept #RGB/#RGBA/#RRGGBBAA, so skip straight to the real icon rather
  -- than mis-parse a color shorthand into a garbled flash.
  if not target:match("^#%x%x%x%x%x%x$") then
    regenerate(cfg, percent, charging, powerSaver, dataDir)
    return
  end
  local flash = blendHex(target, "#FFFFFF", 0.85)
  pendingAnim = {
    cfg = cfg,
    percent = percent,
    charging = charging,
    powerSaver = powerSaver,
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
      noctalia.runAsync("@powerprofilesctl@ get", function(profileResult)
        local powerSaver = trim(profileResult.stdout) == "power-saver"
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
          .. (powerSaver and "s" or "n")
          .. cfg.lowColor
          .. cfg.mediumColor
          .. cfg.highColor
          .. cfg.chargingColor
          .. cfg.chargingBoltColor
          .. cfg.powerSaverColor
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
          startPulse(cfg, percent, charging, powerSaver, dataDir)
        else
          regenerate(cfg, percent, charging, powerSaver, dataDir)
        end
      end, 5000)
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
