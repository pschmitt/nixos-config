Name = "home-assistant"
NamePretty = "Home Assistant"
Icon = "home"
Terminal = false
Cache = false
FixedOrder = true
Action = "lua:ActionDefault"
SearchName = true

local RUNTIME_DIR = os.getenv("XDG_RUNTIME_DIR") or ("/run/user/" .. (os.getenv("UID") or "1000"))
local CACHE_FILE = RUNTIME_DIR .. "/elephant-ha/states.json"
local HELPER = "ha-walker"

local CACHED_DATA = nil
local LAST_CHECK = 0

local function shell_quote(v)
  return string.format("%q", v or "")
end

local function load_states()
  local now = os.time()
  if CACHED_DATA and (now - LAST_CHECK) < 1 then
    return CACHED_DATA
  end

  local f = io.open(CACHE_FILE, "r")
  if not f then
    os.execute("(" .. HELPER .. " sync >/dev/null 2>&1) &")
    return CACHED_DATA or {}
  end

  local content = f:read("*a")
  f:close()

  if not content or content == "" then
    return CACHED_DATA or {}
  end

  local ok, data = pcall(jsonDecode, content)
  if ok and type(data) == "table" then
    CACHED_DATA = data
    LAST_CHECK = now
    return data
  end

  return CACHED_DATA or {}
end

function ActionDefault(val)
  CACHED_DATA = nil
  os.execute("(" .. HELPER .. " toggle " .. shell_quote(val) .. " >/dev/null 2>&1) &")
end

function ActionToggle(val)
  CACHED_DATA = nil
  os.execute("(" .. HELPER .. " toggle " .. shell_quote(val) .. " >/dev/null 2>&1) &")
end

function ActionUp(val)
  CACHED_DATA = nil
  os.execute("(" .. HELPER .. " up " .. shell_quote(val) .. " >/dev/null 2>&1) &")
end

function ActionDown(val)
  CACHED_DATA = nil
  os.execute("(" .. HELPER .. " down " .. shell_quote(val) .. " >/dev/null 2>&1) &")
end

function ActionPin(val)
  os.execute(HELPER .. " toggle-pin " .. shell_quote(val))
  CACHED_DATA = nil
end

function ActionCopy(val)
  os.execute(HELPER .. " copy " .. shell_quote(val))
end

function ActionOpen(val)
  os.execute("(" .. HELPER .. " open " .. shell_quote(val) .. " >/dev/null 2>&1) &")
end

function ActionRefresh()
  os.execute(HELPER .. " sync")
  CACHED_DATA = nil
end

function ActionSetTemp(val)
  CACHED_DATA = nil
  local eid, temp = val:match("^([^:]+):(.*)$")
  if eid and temp then
    os.execute("(" .. HELPER .. " set-temp " .. shell_quote(eid) .. " " .. shell_quote(temp) .. " >/dev/null 2>&1) &")
  end
end

function ActionSetBrightness(val)
  CACHED_DATA = nil
  local eid, pct = val:match("^([^:]+):(.*)$")
  if eid and pct then
    local cmd = HELPER .. " set-brightness " .. shell_quote(eid) .. " " .. shell_quote(pct)
    os.execute("(" .. cmd .. " >/dev/null 2>&1) &")
  end
end

function ActionSetFanSpeed(val)
  CACHED_DATA = nil
  local eid, pct = val:match("^([^:]+):(.*)$")
  if eid and pct then
    local cmd = HELPER .. " set-fan-speed " .. shell_quote(eid) .. " " .. shell_quote(pct)
    os.execute("(" .. cmd .. " >/dev/null 2>&1) &")
  end
end

local function trim(s)
  return (s or ""):match("^%s*(.-)%s*$") or ""
end

local function clean_q(s)
  local c = (s or ""):gsub("°", ""):lower()
  return trim(c)
end

local function matches_filter(item, filter)
  if not filter or filter == "" then
    return true
  end
  local parts = { item.name or "", item.id or "", item.area or "", item.keywords or "" }
  local haystack = table.concat(parts, " "):lower()
  for word in filter:lower():gmatch("%S+") do
    if not haystack:find(word, 1, true) then
      return false
    end
  end
  return true
end

local function parse_brightness(raw)
  local q = clean_q(raw)
  local p1, pct, rest = q:match("^(bright%w*)%s+(%d+)%%?%s*(.*)$")
  if not p1 then p1, pct, rest = q:match("^(dim%w*)%s+(%d+)%%?%s*(.*)$") end
  if p1 and pct then return pct, trim(rest) end

  local p2, flt, num = q:match("^(bright%w*)%s+(.-)%s+(%d+)%%?$")
  if not p2 then p2, flt, num = q:match("^(dim%w*)%s+(.-)%s+(%d+)%%?$") end
  if p2 and flt and num then return num, trim(flt) end

  local f3, _, n3 = q:match("^(.-)%s+(bright%w*)%s+(%d+)%%?$")
  if not f3 then f3, _, n3 = q:match("^(.-)%s+(dim%w*)%s+(%d+)%%?$") end
  if f3 and n3 then return n3, trim(f3) end

  local f4, n4 = q:match("^(.-)%s+(%d+)%%$")
  if f4 and n4 then return n4, trim(f4) end

  return nil, nil
end

local function parse_temp(raw)
  local q = clean_q(raw)
  local p1, temp, rest = q:match("^(temp%w*)%s+(%d+%.?%d*)c?%s*(.*)$")
  if not p1 then p1, temp, rest = q:match("^(heat%w*)%s+(%d+%.?%d*)c?%s*(.*)$") end
  if not p1 then p1, temp, rest = q:match("^(setpoint%w*)%s+(%d+%.?%d*)c?%s*(.*)$") end
  if p1 and temp then return temp, trim(rest) end

  local p2, flt, num = q:match("^(temp%w*)%s+(.-)%s+(%d+%.?%d*)c?$")
  if not p2 then p2, flt, num = q:match("^(heat%w*)%s+(.-)%s+(%d+%.?%d*)c?$") end
  if not p2 then p2, flt, num = q:match("^(setpoint%w*)%s+(.-)%s+(%d+%.?%d*)c?$") end
  if p2 and flt and num then return num, trim(flt) end

  local f3, _, n3 = q:match("^(.-)%s+(temp%w*)%s+(%d+%.?%d*)c?$")
  if not f3 then f3, _, n3 = q:match("^(.-)%s+(heat%w*)%s+(%d+%.?%d*)c?$") end
  if not f3 then f3, _, n3 = q:match("^(.-)%s+(setpoint%w*)%s+(%d+%.?%d*)c?$") end
  if f3 and n3 then return n3, trim(f3) end

  local f4, n4 = q:match("^(.-)%s+(%d+%.?%d*)c$")
  if f4 and n4 then return n4, trim(f4) end

  return nil, nil
end

local function parse_fan(raw)
  local q = clean_q(raw)
  local p1, spd, rest = q:match("^(fan%w*)%s+(%d+)%%?%s*(.*)$")
  if not p1 then p1, spd, rest = q:match("^(speed%w*)%s+(%d+)%%?%s*(.*)$") end
  if p1 and spd then return spd, trim(rest) end

  local p2, flt, num = q:match("^(fan%w*)%s+(.-)%s+(%d+)%%?$")
  if not p2 then p2, flt, num = q:match("^(speed%w*)%s+(.-)%s+(%d+)%%?$") end
  if p2 and flt and num then return num, trim(flt) end

  local f3, _, n3 = q:match("^(.-)%s+(fan%w*)%s+(%d+)%%?$")
  if not f3 then f3, _, n3 = q:match("^(.-)%s+(speed%w*)%s+(%d+)%%?$") end
  if f3 and n3 then return n3, trim(f3) end

  return nil, nil
end

function GetEntries(query)
  local data = load_states()
  local raw_q = query or ""
  local q = trim(raw_q:lower())

  -- 1. Quick light brightness setting: "bright 80 office", "dim 50 bedroom", "office 80%"
  local target_bright, bright_filter = parse_brightness(q)
  if target_bright then
    local entries = {}
    for _, item in ipairs(data) do
      if item.domain == "light" and matches_filter(item, bright_filter) then
        table.insert(entries, {
          Text = "💡 Set " .. item.name .. " brightness to " .. target_bright .. "%",
          Subtext = "Light • " .. (item.area or "Home") .. " • [↵ Set Brightness • ^U +15% • ^D -15% • ^P Pin]",
          Icon = "lightbulb",
          Value = item.id .. ":" .. target_bright,
          Keywords = {
            raw_q,
            q,
            "bright " .. target_bright,
            "brightness " .. target_bright,
            item.name:lower(),
            item.id,
            item.area and item.area:lower() or "",
            bright_filter,
          },
          Actions = {
            ["default"] = "lua:ActionSetBrightness",
            ["toggle"]  = "lua:ActionToggle",
            ["up"]      = "lua:ActionUp",
            ["down"]    = "lua:ActionDown",
            ["pin"]     = "lua:ActionPin",
            ["copy"]    = "lua:ActionCopy",
            ["open"]    = "lua:ActionOpen",
            ["refresh"] = "lua:ActionRefresh",
          },
        })
      end
    end
    if #entries > 0 then
      return entries
    end
  end

  -- 2. Quick thermostat target temperature setting: "temp 21 office", "heat 22 living room"
  local target_temp, temp_filter = parse_temp(q)
  if target_temp then
    local entries = {}
    for _, item in ipairs(data) do
      if item.domain == "climate" and matches_filter(item, temp_filter) then
        table.insert(entries, {
          Text = "🌡️ Set " .. item.name .. " to " .. target_temp .. "°C",
          Subtext = "Climate • " .. (item.area or "Thermostat") .. " • [↵ Set Temp • ^U +0.5°C • ^D -0.5°C • ^P Pin]",
          Icon = "weather-clear",
          Value = item.id .. ":" .. target_temp,
          Keywords = {
            raw_q,
            q,
            "temp " .. target_temp,
            "heat " .. target_temp,
            item.name:lower(),
            item.id,
            item.area and item.area:lower() or "",
            temp_filter,
          },
          Actions = {
            ["default"] = "lua:ActionSetTemp",
            ["toggle"]  = "lua:ActionToggle",
            ["up"]      = "lua:ActionUp",
            ["down"]    = "lua:ActionDown",
            ["pin"]     = "lua:ActionPin",
            ["copy"]    = "lua:ActionCopy",
            ["open"]    = "lua:ActionOpen",
            ["refresh"] = "lua:ActionRefresh",
          },
        })
      end
    end
    if #entries > 0 then
      return entries
    end
  end

  -- 3. Quick fan speed setting: "fan 50 office", "speed 75 bedroom"
  local target_fan, fan_filter = parse_fan(q)
  if target_fan then
    local entries = {}
    for _, item in ipairs(data) do
      if item.domain == "fan" and matches_filter(item, fan_filter) then
        table.insert(entries, {
          Text = "🌀 Set " .. item.name .. " speed to " .. target_fan .. "%",
          Subtext = "Fan • " .. (item.area or "Fan") .. " • [↵ Set Speed • ^U +25% • ^D -25% • ^P Pin]",
          Icon = "weather-windy",
          Value = item.id .. ":" .. target_fan,
          Keywords = {
            raw_q,
            q,
            "fan " .. target_fan,
            "speed " .. target_fan,
            item.name:lower(),
            item.id,
            item.area and item.area:lower() or "",
            fan_filter,
          },
          Actions = {
            ["default"] = "lua:ActionSetFanSpeed",
            ["toggle"]  = "lua:ActionToggle",
            ["up"]      = "lua:ActionUp",
            ["down"]    = "lua:ActionDown",
            ["pin"]     = "lua:ActionPin",
            ["copy"]    = "lua:ActionCopy",
            ["open"]    = "lua:ActionOpen",
            ["refresh"] = "lua:ActionRefresh",
          },
        })
      end
    end
    if #entries > 0 then
      return entries
    end
  end

  -- 4. General search: filter items by tokens if query is present
  local entries = {}
  local pinned_entries = {}
  local active_entries = {}
  local other_entries = {}
  local has_filter = q ~= ""

  local function make_entry(item)
    return {
      Text = (item.pinned and "📌 " or "") .. item.name,
      Subtext = item.subtext or (item.domain .. " • " .. item.state),
      Icon = item.icon or "home",
      Value = item.id,
      Keywords = {
        raw_q,
        q,
        item.keywords or "",
        item.domain or "",
        item.id or "",
        item.name or "",
        item.area or "",
        item.state or "",
      },
      Actions = {
        ["default"] = "lua:ActionDefault",
        ["toggle"]  = "lua:ActionToggle",
        ["up"]      = "lua:ActionUp",
        ["down"]    = "lua:ActionDown",
        ["pin"]     = "lua:ActionPin",
        ["copy"]    = "lua:ActionCopy",
        ["open"]    = "lua:ActionOpen",
        ["refresh"] = "lua:ActionRefresh",
      },
    }
  end

  for _, item in ipairs(data) do
    if not has_filter or matches_filter(item, q) then
      local entry = make_entry(item)
      local is_active = item.state == "on"
        or item.state == "open"
        or item.state == "heat"
        or item.state == "cleaning"
        or item.state == "playing"
        or item.state == "unlocked"

      if item.pinned then
        table.insert(pinned_entries, entry)
      elseif is_active then
        table.insert(active_entries, entry)
      else
        table.insert(other_entries, entry)
      end
    end
  end

  for _, e in ipairs(pinned_entries) do table.insert(entries, e) end
  for _, e in ipairs(active_entries) do table.insert(entries, e) end
  for _, e in ipairs(other_entries) do table.insert(entries, e) end

  -- Fallback: if token filter matched nothing, return all items so Elephant can fuzzy match typos
  if #entries == 0 and has_filter then
    for _, item in ipairs(data) do
      table.insert(entries, make_entry(item))
    end
  end

  return entries
end
