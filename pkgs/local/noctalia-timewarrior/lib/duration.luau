--!nonstrict
-- Duration formatting shared by bar.luau and panel.luau. Every duration this
-- plugin displays (state.duration, week/month/year totals, day breakdown) is
-- "H:MM" text from pkgs/local/timew-status's --minutes flag, so parsing it is
-- the same everywhere.
--
-- The time_format setting uses {hours}/{minutes} placeholder substitution —
-- the same {token} style noctalia.tr() uses for translation strings
-- elsewhere in this codebase — rather than strftime, which has no meaning
-- for an elapsed duration (as opposed to a wall-clock time).

local M = {}

M.DEFAULT_FORMAT = "{hours}h {minutes}m"

function M.format(duration, fmt)
  duration = duration or ""
  local h, m = duration:match("^(%d+):(%d+)")
  if not h then
    return duration
  end
  fmt = (fmt and fmt ~= "") and fmt or M.DEFAULT_FORMAT
  local hours = tonumber(h) or 0
  local minutes = tonumber(m) or 0
  return (fmt:gsub("{hours}", tostring(hours)):gsub("{minutes}", string.format("%02d", minutes)))
end

return M
