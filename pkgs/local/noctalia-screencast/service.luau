--!nonstrict
-- Screencast indicator poller — the headless [[service]] entry.
--
-- Detection is intentionally *not* reimplemented here: it stays in the
-- existing Hyprland-side pipeline (screencast.sh + xdg-portal-screencast-
-- watcher.sh, see plugin.toml header), which busctl-monitors the
-- xdg-desktop-portal D-Bus ScreenCast interface and cross-checks PipeWire
-- links to name the screensharing app(s). This just tails the JSON state
-- file that pipeline already maintains for other consumers (the Waybar
-- module it replaces, and the Home Assistant sensor script).

-- TMPDIR is unset in this graphical session, so both screencast.sh and this
-- poller resolve the same "${TMPDIR:-/tmp}" default independently; there's
-- no env passthrough between a Luau plugin service and the shell scripts to
-- keep them pointed at literally the same path otherwise.
local STATEFILE = "/tmp/screencast.json"

local lastKey = ""

local function pollMs()
  return (tonumber(noctalia.getConfig("poll_interval")) or 2) * 1000
end

local function poll()
  local raw = noctalia.readFile(STATEFILE)
  local data = raw and noctalia.json.decode(raw) or nil

  local active = data ~= nil and data.state == "on"
  local apps = (data and data.apps) or {}
  local output = (data and data.output) or ""

  local key = tostring(active) .. "|" .. tostring(output) .. "|" .. table.concat(apps, ",")
  if key == lastKey then
    return
  end
  lastKey = key

  noctalia.state.set("screencast_status", {
    active = active,
    output = output,
    apps = apps,
  })
end

poll()

function update()
  noctalia.setUpdateInterval(pollMs())
  poll()
end
