--!nonstrict
-- Shared status -> composited-badge-icon mapping, used by bar.luau,
-- panel.luau, and desktop.luau so all three show the same icon. Maps the
-- richer rylos/syncthing state set onto the four DMS syncshell badge icons
-- (pkgs/local/syncshell-dank-widget): real problems win over "still
-- starting up", which wins over "paused".

local M = {}

local ICONS = {
  error = "issue",
  offline = "issue",
  unauthorized = "issue",
  disconnected = "issue",
  syncing = "syncing",
  unconfigured = "syncing",
  paused = "paused",
  idle = "synced",
}

function M.path(state)
  local kind = ICONS[state] or "synced"
  return `assets/status-{kind}.png`
end

return M
