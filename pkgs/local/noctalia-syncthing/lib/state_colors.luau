-- State colors shared by the bar and detail panel.

local DEFAULTS = {
  idle = "primary",
  syncing = "secondary",
  paused = "outline",
  disconnected = "secondary",
  offline = "error",
  unauthorized = "error",
  error = "error",
  unconfigured = "outline",
  disabled = "outline",
}

local function get(state)
  return noctalia.getConfig(`{state}_color`) or DEFAULTS[state] or "outline"
end

return {
  defaults = DEFAULTS,
  get = get,
}
