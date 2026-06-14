Name = "obs-reaction"
NamePretty = "OBS Studio Emoji Reaction"
Icon = "camera-video"
Terminal = false
Cache = false
FixedOrder = true
Action = "lua:React"

local CONFIG_DIR = os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")
local DATA_DIR   = (os.getenv("XDG_DATA_HOME") or (os.getenv("HOME") .. "/.local/share")) .. "/elephant"
local EMOJI_LIST = CONFIG_DIR .. "/elephant/emoji-list.txt"

local function ensure_dir(path)
  os.execute("mkdir -p '" .. path .. "'")
end

local function read_list(path)
  local items, seen = {}, {}
  local f = io.open(path, "r")
  if f then
    for line in f:lines() do
      local e = line:match("^(.-)%s*$")
      if e ~= "" and not seen[e] then
        table.insert(items, e)
        seen[e] = true
      end
    end
    f:close()
  end
  return items, seen
end

local function write_list(path, items)
  local f = io.open(path, "w")
  if f then
    for _, e in ipairs(items) do
      f:write(e .. "\n")
    end
    f:close()
  end
end

function React(value, args, query)
  ensure_dir(DATA_DIR)
  local hist = DATA_DIR .. "/obs-reaction-history"
  local items, _ = read_list(hist)
  local new_items = { value }
  for _, e in ipairs(items) do
    if e ~= value then
      table.insert(new_items, e)
      if #new_items >= 10 then break end
    end
  end
  write_list(hist, new_items)

  local tmp = os.tmpname()
  local tf = io.open(tmp, "w")
  if tf then
    tf:write(value)
    tf:close()
    os.execute("(obs-control react " .. string.format("%q", value) .. " 2>/dev/null; rm -f " .. tmp .. ") &")
  end
end

local function parse_lines(fh)
  local emoji_map, ordered = {}, {}
  for line in fh:lines() do
    local emoji = line:match("^(%S+)")
    local name  = line:match("^%S+%s+(%S+)")
    local rest  = line:match("^%S+%s+%S+%s+(.+)$")
    if emoji and not emoji_map[emoji] then
      local entry = {
        Text    = name and name:gsub("_", " ") or emoji,
        Subtext = rest or "",
        Value   = emoji,
        Icon    = emoji,
      }
      emoji_map[emoji] = entry
      table.insert(ordered, entry)
    end
  end
  return emoji_map, ordered
end

local function make_entry(x, subtext)
  return {
    Text    = x.Text,
    Subtext = subtext,
    Value   = x.Value,
    Icon    = x.Icon,
    Actions = {
      ["default"] = "lua:React",
    },
  }
end

function GetEntries()
  local history, hist_set = read_list(DATA_DIR .. "/obs-reaction-history")

  local f = io.open(EMOJI_LIST, "r")
  local emoji_map, ordered = {}, {}
  if f then
    emoji_map, ordered = parse_lines(f)
    f:close()
  end

  local result = {}

  for _, e in ipairs(history) do
    local x = emoji_map[e]
    if x then table.insert(result, make_entry(x, "recently used")) end
  end

  for _, e in ipairs(ordered) do
    if not hist_set[e.Value] then
      table.insert(result, make_entry(e, e.Subtext))
    end
  end

  return result
end
