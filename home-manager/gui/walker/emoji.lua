Name = "emoji"
NamePretty = "Emoji"
Icon = "face-smile"
Terminal = false
Cache = false
FixedOrder = true
Action = "lua:Copy"

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

function Copy(value, args, query)
  -- io.popen:close() blocks until wl-copy exits; run it asynchronously instead
  local tmp = os.tmpname()
  local tf = io.open(tmp, "w")
  if tf then
    tf:write(value)
    tf:close()
    os.execute("(wl-copy <" .. tmp .. " 2>/dev/null; rm -f " .. tmp .. ") &")
  end

  ensure_dir(DATA_DIR)
  local hist = DATA_DIR .. "/emoji-history"
  local items, _ = read_list(hist)
  local new_items = { value }
  for _, e in ipairs(items) do
    if e ~= value then
      table.insert(new_items, e)
      if #new_items >= 10 then break end
    end
  end
  write_list(hist, new_items)

  os.execute("notify-send -a walker-menu " .. string.format("%q", value) .. " 'Copied to clipboard' 2>/dev/null &")
end

function TogglePin(value, args, query)
  ensure_dir(DATA_DIR)
  local pins = DATA_DIR .. "/emoji-pins"
  local items, _ = read_list(pins)

  local found = false
  local new_items = {}
  for _, e in ipairs(items) do
    if e == value then
      found = true
    else
      table.insert(new_items, e)
    end
  end

  if not found then
    table.insert(new_items, 1, value)
  end

  write_list(pins, new_items)
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
      ["default"]         = "lua:Copy",
      ["toggle-pin"] = "lua:TogglePin",
    },
  }
end

function GetEntries()
  local favorites, fav_set  = read_list(DATA_DIR .. "/emoji-pins")
  local history,   hist_set = read_list(DATA_DIR .. "/emoji-history")

  local f = io.open(EMOJI_LIST, "r")
  local emoji_map, ordered = {}, {}
  if f then
    emoji_map, ordered = parse_lines(f)
    f:close()
  end

  local result = {}

  for _, e in ipairs(favorites) do
    local x = emoji_map[e]
    if x then table.insert(result, make_entry(x, "📌 pinned")) end
  end

  for _, e in ipairs(history) do
    if not fav_set[e] then
      local x = emoji_map[e]
      if x then table.insert(result, make_entry(x, "recently used")) end
    end
  end

  for _, e in ipairs(ordered) do
    if not fav_set[e.Value] and not hist_set[e.Value] then
      table.insert(result, make_entry(e, e.Subtext))
    end
  end

  return result
end
