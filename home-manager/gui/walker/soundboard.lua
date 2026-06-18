Name = "soundboard"
NamePretty = "Soundboard"
Icon = "audio-x-generic"
Terminal = false
Cache = false
FixedOrder = true
Action = "lua:DefaultAction"
History = true
HistoryWhenEmpty = true

local DATA_DIR = (os.getenv("XDG_DATA_HOME") or (os.getenv("HOME") .. "/.local/share")) .. "/elephant"
local LANG_FILE = DATA_DIR .. "/soundboard-tts-lang"
local SOUND_DIR = (os.getenv("SOUNDBOARD_DIR") or (os.getenv("HOME") .. "/Music/Soundboard"))
local ZHJ_BIN = (os.getenv("HOME") .. "/bin/zhj")
local CACHED_SOUNDS = nil

local function shell_quote(value)
  return string.format("%q", value or "")
end

local function lowercase(value)
  return (value or ""):lower()
end

local function trim(value)
  return (value or ""):match("^%s*(.-)%s*$")
end

local function normalize_query(value)
  local text = trim(value)

  if text:sub(1, 1) == "," then
    text = trim(text:sub(2))
  end

  return text
end

local function strip_extension(value)
  return (value or ""):gsub("%..*$", "")
end

local function ensure_data_dir()
  os.execute("mkdir -p " .. shell_quote(DATA_DIR))
end

local function get_tts_lang()
  local handle = io.open(LANG_FILE, "r")

  if handle then
    local value = trim(handle:read("*l") or "")
    handle:close()

    if value ~= "" then
      return value
    end
  end

  return "en"
end

local function set_tts_lang(lang)
  ensure_data_dir()

  local handle = io.open(LANG_FILE, "w")
  if handle then
    handle:write(lang .. "\n")
    handle:close()
  end
end

local function notify(message)
  os.execute("notify-send -a walker-menu " .. shell_quote(message) .. " 2>/dev/null &")
end

local function run_async(command)
  os.execute("(" .. command .. " >/dev/null 2>&1) &")
end

local function speak(lang, text)
  local normalized = trim(text)

  if normalized == "" then
    return
  end

  set_tts_lang(lang)
  notify("🗣️ TTS (" .. lang .. "): " .. normalized)
  run_async(shell_quote(ZHJ_BIN) .. " soundboard::tts --lang " .. shell_quote(lang) .. " " .. shell_quote(normalized))
end

local function speak_ha(lang, text)
  local normalized = trim(text)

  if normalized == "" then
    return
  end

  set_tts_lang(lang)
  notify("☁️ TTS (" .. lang .. "): " .. normalized)
  run_async(shell_quote(ZHJ_BIN) .. " soundboard::tts --ha --lang " .. shell_quote(lang) .. " " .. shell_quote(normalized))
end

local function play_sound(name)
  if trim(name) == "" then
    return
  end

  run_async("soundboard play " .. shell_quote(name))
end

local function split_value(value)
  local kind, payload = (value or ""):match("^([^:]+):(.*)$")
  return kind, payload
end

function DefaultAction(value, args, query)
  local kind, payload = split_value(value)

  if kind == "tts" then
    speak(get_tts_lang(), normalize_query(payload ~= "" and payload or query))
    return
  end

  if kind == "sound" then
    play_sound(payload)
  end
end

function TtsEnglish(value, args, query)
  local kind, payload = split_value(value)
  speak("en", normalize_query(kind == "tts" and payload or query))
end

function TtsGerman(value, args, query)
  local kind, payload = split_value(value)
  speak("de", normalize_query(kind == "tts" and payload or query))
end

function TtsHomeAssistant(value, args, query)
  local kind, payload = split_value(value)
  speak_ha(get_tts_lang(), normalize_query(kind == "tts" and payload or query))
end

local function load_sounds()
  if CACHED_SOUNDS ~= nil then
    return CACHED_SOUNDS
  end

  local sounds = {}
  local seen = {}
  local handle = io.popen("find " .. shell_quote(SOUND_DIR) .. " -maxdepth 1 -type f -printf '%f\\n' 2>/dev/null")

  if handle then
    for line in handle:lines() do
      local sound = strip_extension(trim(line))
      if sound ~= "" and not seen[sound] then
        table.insert(sounds, sound)
        seen[sound] = true
      end
    end
    handle:close()
  end

  table.sort(sounds)
  CACHED_SOUNDS = sounds
  return CACHED_SOUNDS
end

local function exact_match(sounds, query)
  local needle = lowercase(trim(query))

  if needle == "" then
    return false
  end

  for _, sound in ipairs(sounds) do
    if lowercase(sound) == needle then
      return true
    end
  end

  return false
end

local function partial_match(sounds, query)
  local needle = lowercase(trim(query))

  if needle == "" then
    return false
  end

  for _, sound in ipairs(sounds) do
    if lowercase(sound):find(needle, 1, true) ~= nil then
      return true
    end
  end

  return false
end

local function make_tts_entry(raw_query, query, lang, has_partial_match)
  local text = normalize_query(query)
  local trimmed_raw_query = trim(raw_query)
  local subtext = "Press Ctrl+E for English or Ctrl+D for German"

  if has_partial_match then
    subtext = "TTS fallback in " .. lang .. " • " .. subtext
  else
    subtext = "No sound match • TTS in " .. lang .. " • " .. subtext
  end

  return {
    Text = "🗣️ " .. text,
    Subtext = subtext,
    Value = "tts:" .. text,
    Icon = "audio-input-microphone",
    Keywords = {
      raw_query,
      trimmed_raw_query,
      "," .. text,
      ", " .. text,
    },
    Actions = {
      ["default"] = "lua:DefaultAction",
      ["tts-en"] = "lua:TtsEnglish",
      ["tts-de"] = "lua:TtsGerman",
      ["tts-ha"] = "lua:TtsHomeAssistant",
    },
  }
end

local function make_tts_hint_entry()
  return {
    Text = "🗣️ TTS mode",
    Subtext = "Type after ',' to speak • Ctrl+E English • Ctrl+D German",
    Value = "tts:",
    Icon = "audio-input-microphone",
    Keywords = { "," },
    Actions = {
      ["default"] = "lua:DefaultAction",
      ["tts-en"] = "lua:TtsEnglish",
      ["tts-de"] = "lua:TtsGerman",
      ["tts-ha"] = "lua:TtsHomeAssistant",
    },
  }
end

local function make_sound_entry(sound)
  return {
    Text = sound,
    Subtext = "Play soundboard clip",
    Value = "sound:" .. sound,
    Icon = "audio-x-generic",
    Actions = {
      ["default"] = "lua:DefaultAction",
    },
  }
end

function GetEntries(query)
  local sounds = load_sounds()
  local result = {}
  local raw_text = query or ""
  local trimmed_raw_text = trim(raw_text)
  local text = normalize_query(query)

  if trimmed_raw_text == "," then
    table.insert(result, make_tts_hint_entry())
  end

  if text ~= "" and not exact_match(sounds, text) then
    table.insert(result, make_tts_entry(raw_text, text, get_tts_lang(), partial_match(sounds, text)))
  end

  for _, sound in ipairs(sounds) do
    table.insert(result, make_sound_entry(sound))
  end

  return result
end
