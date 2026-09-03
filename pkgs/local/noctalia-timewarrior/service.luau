--!nonstrict
-- Timewarrior poller — the headless [[service]] entry.
--
-- Shells out to timew-is-on / timew-total / timew-week-breakdown (from
-- pkgs/local/timew-status, absolute paths substituted at build time) and
-- publishes two snapshots: "tw_status" (current tracking state, for
-- bar.luau) and "tw_summary" (week/month/year totals + day breakdown, for
-- panel.luau).

local function trim(s)
  return noctalia.string.trim(s or "")
end

local function pollMs()
  return (tonumber(noctalia.getConfig("poll_interval")) or 5) * 1000
end

local summary = { week = "0:00", month = "0:00", year = "0:00", days = {} }

local function publishSummary()
  noctalia.state.set("tw_summary", summary)
end

local function parseWeekBreakdown(text)
  local days = {}
  for line in text:gmatch("[^\n]+") do
    local date, dow, duration = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)$")
    if date then
      table.insert(days, { date = date, dow = dow, duration = duration })
    end
  end
  return days
end

local function refreshSummary()
  noctalia.runAsync("@timewTotal@ --minutes :week", function(r)
    local d = trim(r.stdout)
    summary.week = d ~= "" and d or "0:00"
    publishSummary()
  end, 5000)

  noctalia.runAsync("@timewTotal@ --minutes :month", function(r)
    local d = trim(r.stdout)
    summary.month = d ~= "" and d or "0:00"
    publishSummary()
  end, 5000)

  noctalia.runAsync("@timewTotal@ --minutes :year", function(r)
    local d = trim(r.stdout)
    summary.year = d ~= "" and d or "0:00"
    publishSummary()
  end, 5000)

  noctalia.runAsync("@timewWeekBreakdown@", function(r)
    summary.days = parseWeekBreakdown(trim(r.stdout))
    publishSummary()
  end, 5000)
end

local function poll()
  noctalia.runAsync("@timewIsOn@", function(isOnResult)
    local active = isOnResult.exitCode == 0

    if not active then
      noctalia.state.set("tw_status", { active = false, duration = "" })
      return
    end

    noctalia.runAsync("@timewTotal@ --minutes", function(totalResult)
      noctalia.state.set("tw_status", {
        active = true,
        duration = trim(totalResult.stdout),
      })
    end, 5000)
  end, 5000)

  refreshSummary()
end

poll()

function update()
  noctalia.setUpdateInterval(pollMs())
  poll()
end
