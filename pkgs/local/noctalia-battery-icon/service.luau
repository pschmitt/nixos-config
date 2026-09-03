--!nonstrict
-- Battery icon poller — renders a small PNG (rounded pill, charge-tier
-- color, percentage baked into the body) via ImageMagick whenever the
-- charge level or plugged-in state changes, Android-status-bar style.
--
-- The bar-widget ui.* framework (row/column/box/label, all pure flex
-- layout) has no overlay/z-stack primitive, and even Noctalia's own
-- built-in "graphic" battery display mode places its percentage label
-- beside the icon, not on top of it (confirmed against battery_widget.cpp
-- upstream). A live-generated bitmap is the only way to draw the number
-- literally inside the shape instead of next to it.

local BAT = "BAT0"
local CAPACITY_PATH = "/sys/class/power_supply/" .. BAT .. "/capacity"
local STATUS_PATH = "/sys/class/power_supply/" .. BAT .. "/status"

local function trim(s)
  return noctalia.string.trim(s or "")
end

local lastKey = ""
-- Bumped whenever the generated icon's look changes (size, colors, font),
-- so stale cached PNGs from an older version of this script don't linger
-- and get reused just because the percent+charging key matches.
local ICON_VERSION = "v2"

local function tierColors(percent, charging)
  if charging then
    return "#B6C4FF", "#11131A" -- primary (Indigo palette)
  end
  if percent < 20 then
    return "#FF6B81", "#11131A" -- red
  end
  if percent < 50 then
    return "#F2C94C", "#11131A" -- amber
  end
  return "#6FCF97", "#11131A" -- green
end

local function regenerate(percent, charging, dataDir)
  local bg, fg = tierColors(percent, charging)
  local label = tostring(percent) .. "%"
  local outPath = dataDir .. "/battery-" .. ICON_VERSION .. "-" .. tostring(percent) .. (charging and "c" or "d") .. ".png"

  if noctalia.fileExists(outPath) then
    noctalia.state.set("battery_icon", { path = outPath, percent = percent, charging = charging })
    return
  end

  local cmd = "@magick@ -size 128x64 xc:none "
    .. "-fill '"
    .. bg
    .. "' -draw 'roundrectangle 4,6 108,58 10,10' "
    .. "-fill '"
    .. bg
    .. "' -draw 'roundrectangle 108,22 124,42 4,4' "
    .. "-gravity center -fill '"
    .. fg
    .. "' -font '@font@' -pointsize 42 -annotate -8+0 '"
    .. label
    .. "' '"
    .. outPath
    .. "'"

  noctalia.runAsync(cmd, function(result)
    if result.exitCode == 0 then
      noctalia.state.set("battery_icon", { path = outPath, percent = percent, charging = charging })
    else
      noctalia.log("battery-icon: magick failed: " .. trim(result.stderr))
    end
  end, 5000)
end

local function poll()
  noctalia.runAsync("cat " .. CAPACITY_PATH, function(capResult)
    local percent = tonumber(trim(capResult.stdout))
    if percent == nil then
      return
    end

    noctalia.runAsync("cat " .. STATUS_PATH, function(statusResult)
      local status = trim(statusResult.stdout)
      local charging = status == "Charging" or status == "Full"
      local key = tostring(percent) .. (charging and "c" or "d")

      if key == lastKey then
        return
      end
      lastKey = key

      local dataDir = noctalia.pluginDataDir()
      if dataDir ~= nil then
        regenerate(percent, charging, dataDir)
      end
    end, 5000)
  end, 5000)
end

poll()

function update()
  noctalia.setUpdateInterval(15000)
  poll()
end
