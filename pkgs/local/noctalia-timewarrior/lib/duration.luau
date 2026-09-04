--!nonstrict
-- Duration formatting shared by bar.luau and panel.luau. Every duration this
-- plugin displays (state.duration, week/month/year totals, day breakdown) is
-- "H:MM" text from pkgs/local/timew-status's --minutes flag, so parsing it is
-- the same everywhere.
--
-- bar_time_format/panel_time_format use {hours}/{minutes} placeholder
-- substitution — the same {token} style noctalia.tr() uses for translation
-- strings elsewhere in this codebase — rather than strftime, which has no
-- meaning for an elapsed duration (as opposed to a wall-clock time). Each
-- caller resolves its own setting and default; this module just substitutes.

local M = {}

function M.format(duration, fmt)
  duration = duration or ""
  local h, m = duration:match("^(%d+):(%d+)")
  if not h or not fmt or fmt == "" then
    return duration
  end
  local hours = tonumber(h) or 0
  local minutes = tonumber(m) or 0
  return (fmt:gsub("{hours}", tostring(hours)):gsub("{minutes}", string.format("%02d", minutes)))
end

return M
