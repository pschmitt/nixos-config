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

-- Last successfully read power profile. A failed or empty `powerprofilesctl`
-- read is "unknown", not "off": several poll()s fire at once when the shell
-- restarts (the initial poll plus every stream's first line), and treating a
-- dropped read as false made the icon flip its Battery Saver glyph off again
-- moments after correctly showing it -- observed on gk4 as 69ds and 69dn
-- rendered nine seconds apart while the profile never changed.
local lastPowerSaver = false
local lastProfile = nil
local soundReady = { charging = false, unplug = false }

-- "Is external power connected?", most portable source first.
--
-- upower's daemon-level OnBattery property is the canonical answer: it
-- aggregates *every* line-power supply the kernel exposes, so it covers
-- USB-C PD sources and docks as well as a classic barrel jack, on any
-- distro, without us knowing any device names. Prints "b false" when
-- plugged in, "b true" on battery.
--
-- If upower isn't running (busctl exits non-zero) fall back to scanning
-- sysfs for line-power supplies ourselves, selecting them by `type` since
-- the device name isn't portable (AC, ACAD, AC0, ADP1, ...). That prints
-- one 0/1 line per Mains supply, or nothing when the machine exposes none.
local AC_ONLINE_CMD = "@busctl@ --system get-property org.freedesktop.UPower "
  .. "/org/freedesktop/UPower org.freedesktop.UPower OnBattery 2>/dev/null || "
  .. "grep -lx Mains /sys/class/power_supply/*/type 2>/dev/null | sed 's|/type$|/online|' | xargs -r cat 2>/dev/null"

-- The charge level, from upower for the same reasons and — more importantly
-- — from the *same place* as the plug state above. The two sources disagree:
-- upower derives Percentage from energy rather than reading the kernel's
-- capacity, and on this laptop reports 97 where sysfs says 98. So which one
-- wins has to be settled once for the whole widget instead of per read, or
-- the number visibly flickers depending on which path updated it last.
-- Pairing them means upower answers both questions when it's running and
-- sysfs answers both when it isn't; they are never mixed.
--
-- The same call also reports the battery's charge limit, so the two reads
-- cost one process instead of two. Exactly two lines come back: the level
-- ("d 97" from upower's typed double, or a bare "97" from the kernel), then
-- the limit ("u 80", a bare "90", or empty when there is none).
--
-- The limit is only meaningful when the firmware is actually enforcing it.
-- ge2 advertises ChargeEndThreshold=80 while ChargeThresholdEnabled=false
-- and happily charges to 98, so reading the threshold without checking the
-- enabled flag would cap the scale at a limit that isn't in effect. Only
-- when upower is absent entirely do we fall back to the kernel's own knob.
local function batteryCommand(device)
  local dev = "/org/freedesktop/UPower/devices/battery_" .. device
  local prop = "@busctl@ --system get-property org.freedesktop.UPower " .. dev .. " org.freedesktop.UPower.Device "
  return "p=$("
    .. prop
    .. "Percentage 2>/dev/null || cat /sys/class/power_supply/"
    .. device
    .. "/capacity 2>/dev/null); "
    .. "e=$("
    .. prop
    .. "ChargeThresholdEnabled 2>/dev/null); "
    .. 'if [ "$e" = "b true" ]; then l=$('
    .. prop
    .. "ChargeEndThreshold 2>/dev/null); "
    .. 'elif [ -z "$e" ]; then l=$(cat /sys/class/power_supply/'
    .. device
    .. '/charge_control_end_threshold 2>/dev/null); else l=""; fi; '
    .. [[printf '%s\n%s\n' "$p" "$l"]]
end

-- Strips busctl's leading type tag ("d 97", "u 80") when present, so the
-- same parser handles a typed D-Bus reply and a bare sysfs number.
local function parseNumber(s)
  local raw = trim(s)
  local n = tonumber(raw:match("^%a%s+(.+)$") or raw)
  return n ~= nil and math.round(n) or nil
end

-- Highest level observed while external power was connected and the firmware
-- had stopped charging anyway. That is the charge limit making itself
-- visible through behaviour, which is the only way to see it on hardware
-- that exposes no knob at all: gk4 (a GPD G1628-04) caps at 80% purely in
-- BIOS, with no charge_control_* in sysfs, no vendor module, and nothing
-- from upower. Deliberately not persisted -- a stale learned cap would
-- silently distort the tiers long after the BIOS setting changed, and this
-- re-learns within one poll of being plugged in.
local MIN_LEARNABLE_LIMIT = 50
local learnedLimit = nil
local lastLoggedLimit = nil

-- Explicit setting wins, then a limit the firmware actually reports, then
-- what we have watched it do. 100 means "charges to full".
local function effectiveLimit(cfg, reported)
  local limit = 100
  local source = "unlimited"
  if cfg.fullAt > 0 then
    limit, source = cfg.fullAt, "configured"
  elseif reported ~= nil and reported > 0 and reported < 100 then
    limit, source = reported, "reported"
  elseif learnedLimit ~= nil then
    limit, source = learnedLimit, "learned"
  end
  if limit ~= lastLoggedLimit then
    lastLoggedLimit = limit
    noctalia.log("battery-icon: charge limit " .. tostring(limit) .. "% (" .. source .. ")")
  end
  return limit
end

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
    fullAt = math.clamp(tonumber(noctalia.getConfig("full_at")) or 0, 0, 100),
    lowColor = resolveColor(noctalia.getConfig("low_color"), "#EA4335"),
    mediumColor = resolveColor(noctalia.getConfig("medium_color"), "#9AA0A6"),
    highColor = resolveColor(noctalia.getConfig("high_color"), "#9AA0A6"),
    chargingColor = resolveColor(noctalia.getConfig("charging_color"), "#34A853"),
    chargingBoltColor = resolveColor(noctalia.getConfig("charging_bolt_color"), "#FFFFFF"),
    powerSaverPlusColor = resolveColor(noctalia.getConfig("power_saver_plus_color"), "#F1F3F4"),
    textColor = resolveColor(noctalia.getConfig("text_color"), "#202124"),
    emptyColor = resolveColor(noctalia.getConfig("empty_color"), "#F1F3F4"),
  }
end

-- The body colour encodes exactly one fact: how full the battery is (plus
-- the charging state, which can't hide anything since it only applies while
-- powered). It used to also carry the Power Saver profile, which meant a
-- machine left in power-saver -- gk4 lives there -- painted the same orange
-- at 78% and at 8%, so the low-battery colour could never appear. Two
-- independent facts do not fit in one channel; the profile is simply not
-- shown any more.
local function tierColor(cfg, percent, charging)
  if charging then
    return cfg.chargingColor
  end
  -- A firmware charge limit means the battery can never reach 100%, so raw
  -- thresholds permanently understate how full it is: capped at 80%, a pack
  -- one point below its cap is as full as it will ever get, yet reads as 79%
  -- of a full battery. Compare the tiers against the achievable maximum
  -- instead. Only the tiers are rescaled -- regenerate() still draws the true
  -- percentage as both the number and the level fill, so the icon never
  -- misreports the actual charge.
  --
  -- Note this rescales the whole range, not just the top of it: at fullAt=80
  -- a low_threshold of 20 turns red at 16% real charge, since 16/80 = 20%.
  -- The remaining runtime there really is the same as any battery at 16%,
  -- so if that reads as too late, lower the limit rather than the threshold.
  local level = percent
  if cfg.fullAt < 100 then
    level = math.min(percent / cfg.fullAt * 100, 100)
  end
  if level <= cfg.lowThreshold then
    return cfg.lowColor
  end
  if level <= cfg.mediumThreshold then
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

-- Battery Saver, drawn the way Android does it: a "+" occupying the same
-- slot past the body that the terminal and the bolt use. Keeping it out of
-- the body is the whole point -- the body colour stays free to encode the
-- charge level, so a low battery still turns red while saver is on. It
-- yields to the bolt when charging, since that state is the more urgent of
-- the two and the slot only fits one glyph.
-- Positioned to sit slightly *over* the body's right edge, as in Android's
-- own battery-saver icon, rather than clear of it. PLUS_GAP_ARMS is the same
-- glyph grown by 4px on every side, used to punch a transparent gap through
-- the body so the two shapes stay legible where they overlap.
local PLUS_ARMS = { "82,28 112,37", "93,17 102,47" }
local PLUS_GAP_ARMS = { "78,24 116,41", "89,13 106,51" }

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
  local bg = bgOverride or tierColor(cfg, percent, charging)
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
    .. "-"
    .. sanitize(cfg.powerSaverPlusColor)
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
  elseif powerSaver then
    -- Punch the gap first: DstOut with the oversized glyph clears both the
    -- body pixels it overlaps and a margin around the rest, then -compose
    -- Over restores normal drawing for the "+" itself. The bolt solves the
    -- same problem with a stroke, which doesn't work here -- a stroke would
    -- paint a colour, and what this needs is actual transparency so the bar
    -- shows through, matching Android's cut-out.
    cmd = cmd .. "\\( -size 128x64 xc:none -fill white"
    for _, arm in ipairs(PLUS_GAP_ARMS) do
      cmd = cmd .. " -draw 'rectangle " .. arm .. "'"
    end
    cmd = cmd .. " \\) -compose DstOut -composite -compose Over "
    cmd = cmd .. "-fill '" .. cfg.powerSaverPlusColor .. "' "
    for _, arm in ipairs(PLUS_ARMS) do
      cmd = cmd .. "-draw 'rectangle " .. arm .. "' "
    end
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
  local target = tierColor(cfg, percent, charging)
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
  local statusPath = "/sys/class/power_supply/" .. cfg.device .. "/status"

  noctalia.runAsync(batteryCommand(cfg.device), function(capResult)
    -- Two lines: level, then the firmware's charge limit (blank if none).
    local lines = string.split(capResult.stdout or "", "\n")
    local percent = parseNumber(lines[1] or "")
    if percent == nil then
      return
    end
    local reportedLimit = parseNumber(lines[2] or "")

    noctalia.runAsync("cat " .. statusPath, function(statusResult)
      local status = trim(statusResult.stdout)

      noctalia.runAsync(AC_ONLINE_CMD, function(acResult)
        -- The battery's own status describes *current flow*, not whether a
        -- charger is attached. Once the pack sits above the EC's charge
        -- limit, firmware does maintenance cycling: BAT0 alternates
        -- "Charging" and "Discharging" every minute or so with the charger
        -- never leaving the wall (current_now even vanishes with ENODEV
        -- while idle). Deriving the plugged state from status therefore made
        -- the icon, the pulse and the plug/unplug sounds flap on that same
        -- cycle. AC_ONLINE_CMD answers the question we actually mean, and
        -- stays put across the whole maintenance cycle.
        local acOnline = trim(acResult.stdout)
        local charging
        if acOnline:match("^b ") ~= nil then
          charging = acOnline == "b false" -- upower OnBattery
        elseif acOnline ~= "" then
          charging = acOnline:match("1") ~= nil -- sysfs line-power online
        else
          -- Neither upower nor a Mains supply: last-resort status heuristic.
          -- "Not charging" is the power_supply ABI's "AC present but battery
          -- not accepting current", so it counts as plugged in too.
          charging = status == "Charging" or status == "Full" or status == "Not charging"
        end

        -- Plugged in, yet the firmware has stopped charging: whatever the
        -- battery sits at now is at or just under its cap. "Full" counts as
        -- 100, so a normal battery correctly learns no limit at all.
        if charging and (status == "Not charging" or status == "Full") then
          local observed = status == "Full" and 100 or percent
          -- A pause well down the range is a thermal or protection stop, not
          -- a cap. Learning it would be actively dangerous: a "limit" of 40
          -- rescales 30% real charge to 75%, suppressing the low-battery
          -- color exactly when it matters. Firmware caps are offered at 60/
          -- 80/100 in practice, so ignore anything implausibly low.
          if observed >= MIN_LEARNABLE_LIMIT and (learnedLimit == nil or observed > learnedLimit) then
            learnedLimit = observed
          end
        end
        cfg.fullAt = effectiveLimit(cfg, reportedLimit)

        noctalia.runAsync("@powerprofilesctl@ get", function(profileResult)
          local profile = trim(profileResult.stdout)
          local powerSaver
          if profile == "" then
            powerSaver = lastPowerSaver
            noctalia.log(
              "battery-icon: power profile read failed (exit "
                .. tostring(profileResult.exitCode)
                .. "), keeping "
                .. tostring(powerSaver)
            )
          else
            if profile ~= lastProfile then
              noctalia.log("battery-icon: power profile -> " .. profile)
              lastProfile = profile
            end
            powerSaver = profile == "power-saver"
            lastPowerSaver = powerSaver
          end
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
            .. tostring(cfg.fullAt)
            .. cfg.lowColor
            .. cfg.mediumColor
            .. cfg.highColor
            .. cfg.chargingColor
            .. cfg.chargingBoltColor
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
  end, 5000)
end

poll()

-- Everything below is edge-triggered, so poll_interval is only a safety net
-- for machines without upower. Each stream is a
-- long-lived subscription that stays completely silent until something it
-- cares about actually moves.
--
-- All four merely say "something moved" and let poll() re-read the state:
-- none of them feeds its payload into the icon. Keeping every read in one
-- place is what lets poll() apply the upower-or-sysfs choice consistently
-- (see percentCommand) instead of each stream introducing its own source.
-- The streams only decide *when* to read. A duplicate line costs nothing
-- either — poll() is a no-op once the icon is current.

-- `busctl wait` subscribes with an ordinary match rule, so unlike
-- `busctl monitor` (and dbus-monitor) it doesn't need the root-only
-- BecomeMonitor call and works fine from a user session.
-- --limit-messages=infinity turns the one-shot wait into a stream, and
-- --json=short makes each signal one decodable line rather than the
-- pretty-printed GVariant text gdbus produces:
--   {"type":"sa{sv}as","data":["org.freedesktop.UPower",
--    {"OnBattery":{"type":"b","data":false}},[]]}
-- data holds PropertiesChanged's three arguments: interface, changed
-- properties, invalidated property names.
--
-- stdbuf is not optional. busctl block-buffers stdout when it isn't a tty,
-- and these signals are far too small and rare to fill a 4 KiB buffer — a
-- 75 s test run produced literally zero bytes without it.
local function propertiesChangedStream(service, objectPath)
  return "@stdbuf@ -oL @busctl@ --system --json=short --limit-messages=infinity wait "
    .. service
    .. " "
    .. objectPath
    .. " org.freedesktop.DBus.Properties PropertiesChanged"
end

-- Re-poll whenever `property` shows up in a PropertiesChanged payload from
-- `objectPath`. Filtering on the property name is the whole point of taking
-- JSON rather than gdbus's text: upower's *device* objects emit roughly two
-- signals a minute of pure telemetry (UpdateTime, Voltage, EnergyRate,
-- Energy), so an unfiltered subscription there would trigger poll() more
-- often than the old 15 s timer did.
local function watchProperty(service, objectPath, property)
  noctalia.runStream(propertiesChangedStream(service, objectPath), function(line)
    local ok, decoded = pcall(noctalia.json.decode, line)
    if not ok or type(decoded) ~= "table" or type(decoded.data) ~= "table" then
      -- Unrecognized shape: poll anyway rather than risk missing an edge.
      poll()
      return
    end
    local changed = decoded.data[2]
    if type(changed) == "table" and changed[property] ~= nil then
      poll()
    end
  end)
end

-- Plug/unplug. upower's daemon-level OnBattery is the same aggregate
-- AC_ONLINE_CMD reads, and the daemon object carries nothing else we'd
-- confuse it with (only LidIsClosed).
watchProperty("org.freedesktop.UPower", "/org/freedesktop/UPower", "OnBattery")

-- Charge level. upower mangles the kernel's name into its object path, but
-- only for characters that aren't path-safe — a plain "BAT0"/"BATT" passes
-- through untouched. Read once at startup rather than per signal: the
-- battery device can't be swapped without a reboot anyway.
watchProperty(
  "org.freedesktop.UPower",
  "/org/freedesktop/UPower/devices/battery_" .. settings().device,
  "Percentage"
)


-- Battery Saver. power-profiles-daemon still owns the old net.hadess name
-- here; on a build that only exposes org.freedesktop.UPower.PowerProfiles
-- this stream simply never fires and poll_interval picks the change up.
watchProperty("net.hadess.PowerProfiles", "/net/hadess/PowerProfiles", "ActiveProfile")

-- The no-upower path: without the daemon none of the D-Bus streams above
-- ever fire, and the kernel's own power_supply uevents (emitted for both the
-- AC and battery devices on a plug/unplug) still give the same edge.
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
