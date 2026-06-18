Name = "soundboard-tts"
NamePretty = "Soundboard TTS"
Icon = "audio-input-microphone"
Terminal = false
Cache = false
FixedOrder = true
Action = "lua:DefaultAction"
History = true
HistoryWhenEmpty = true

local DATA_DIR = (os.getenv("XDG_DATA_HOME") or (os.getenv("HOME") .. "/.local/share")) .. "/elephant"
local LANG_FILE = DATA_DIR .. "/soundboard-tts-lang"
local ZHJ_BIN = (os.getenv("HOME") .. "/bin/zhj")

local function shell_quote(value)
  return string.format("%q", value or "")
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

function DefaultAction(value, args, query)
  local text = normalize_query(value)

  if text == "" then
    text = normalize_query(query)
  end

  speak(get_tts_lang(), text)
end

function TtsEnglish(value, args, query)
  local text = normalize_query(value)

  if text == "" then
    text = normalize_query(query)
  end

  speak("en", text)
end

function TtsGerman(value, args, query)
  local text = normalize_query(value)

  if text == "" then
    text = normalize_query(query)
  end

  speak("de", text)
end

function TtsHomeAssistant(value, args, query)
  local text = normalize_query(value)

  if text == "" then
    text = normalize_query(query)
  end

  speak_ha(get_tts_lang(), text)
end

function GetEntries(query)
  local text = normalize_query(query)

  if text == "" then
    return {
      {
        Text = "🗣️ Soundboard TTS",
        Subtext = "Type after ',' to speak • Ctrl+E English • Ctrl+D German",
        Value = "",
        Icon = "audio-input-microphone",
        Actions = {
          ["default"] = "lua:DefaultAction",
          ["tts-en"] = "lua:TtsEnglish",
          ["tts-de"] = "lua:TtsGerman",
          ["tts-ha"] = "lua:TtsHomeAssistant",
        },
      },
    }
  end

  return {
    {
      Text = "🗣️ " .. text,
      Subtext = "TTS in " .. get_tts_lang() .. " • Press Ctrl+E for English or Ctrl+D for German",
      Value = text,
      Icon = "audio-input-microphone",
      Actions = {
        ["default"] = "lua:DefaultAction",
        ["tts-en"] = "lua:TtsEnglish",
        ["tts-de"] = "lua:TtsGerman",
        ["tts-ha"] = "lua:TtsHomeAssistant",
      },
    },
  }
end
