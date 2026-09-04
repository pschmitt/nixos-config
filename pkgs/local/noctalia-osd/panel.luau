--!nonstrict
-- Custom OSD toast — shared by both [[panel]] entries. Opened with a JSON
-- payload as context:
--   noctalia msg panel-open pschmitt/osd:toast '{"summary":"...","body":"...","severity":"info","category":"...","command":"...","timeout_ms":4000}'
-- Only "summary" is required; everything else has a sane default. A plain
-- (non-JSON) context string is shown verbatim as the summary, so
-- `panel-open pschmitt/osd:toast "Hello"` also works for a quick one-liner.
--
-- Panel geometry is static per entry, so the manifest declares two: ":compact"
-- (single line) and ":toast" (with a body line). This script fills whichever
-- content box it is handed and does not care which one it is running in — the
-- caller picks by whether the payload has a body. Opening one closes the
-- other, since both live in PanelManager's single active-panel slot.

local SEVERITY = {
  info = { glyph = "info-circle", color = "on_surface" },
  warn = { glyph = "alert-triangle", color = "secondary" },
  error = { glyph = "alert-circle", color = "error" },
}

local STYLE_KEYS = {
  "show_icon",
  "icon",
  "icon_size",
  "icon_color",
  "icon_text_gap",
  "line_gap",
  "padding_h",
  "padding_v",
  "max_text_width",
  "summary_font_size",
  "summary_font_weight",
  "summary_color",
  "body_font_size",
  "body_color",
  "text_align",
  "two_line_balance",
  "content_fill",
  "content_border",
  "content_border_width",
  "content_radius",
  "timeout_ms",
}

local current = nil
local currentStyle = nil
local elapsedSeconds = 0
local timeoutSeconds = nil

local function configValue(key, fallback)
  local value = noctalia.getConfig(key)
  if value == nil then
    return fallback
  end
  return value
end

local function configNumber(key, fallback)
  return tonumber(noctalia.getConfig(key)) or fallback
end

local function copyStyleValues(target, source)
  if type(source) ~= "table" then
    return
  end
  local values = type(source.style) == "table" and source.style or source
  for _, key in ipairs(STYLE_KEYS) do
    if values[key] ~= nil then
      target[key] = values[key]
    end
  end
end

local function expectedMatches(actual, expected, contains)
  if type(expected) == "table" then
    for _, candidate in ipairs(expected) do
      if expectedMatches(actual, candidate, contains) then
        return true
      end
    end
    return false
  end
  if actual == nil then
    return false
  end
  if contains then
    return string.find(tostring(actual), tostring(expected), 1, true) ~= nil
  end
  return tostring(actual) == tostring(expected)
end

local function ruleMatches(rule, payload)
  if type(rule) ~= "table" then
    return false
  end
  if rule.name ~= nil and tostring(payload.profile or "") ~= tostring(rule.name) then
    return false
  end
  if rule.match == nil then
    return true
  end
  if type(rule.match) ~= "table" then
    return false
  end
  for key, expected in pairs(rule.match) do
    local field = tostring(key)
    local contains = string.sub(field, -9) == "_contains"
    if contains then
      field = string.sub(field, 1, #field - 9)
    end
    if not expectedMatches(payload[field], expected, contains) then
      return false
    end
  end
  return true
end

local function applyProfileRules(style, payload)
  local raw = tostring(configValue("profile_rules", "[]"))
  local decoded = noctalia.json.decode(raw)
  if type(decoded) ~= "table" then
    return
  end
  local rules = type(decoded.rules) == "table" and decoded.rules or decoded
  for _, rule in ipairs(rules) do
    if ruleMatches(rule, payload) then
      copyStyleValues(style, rule)
    end
  end
end

local function resolvedStyle(payload)
  local severityName = tostring(payload.severity or "info")
  if SEVERITY[severityName] == nil then
    severityName = "info"
  end
  local severity = SEVERITY[severityName]
  local style = {
    show_icon = configValue("show_icon", true) ~= false,
    icon = tostring(configValue(severityName .. "_icon", severity.glyph)),
    icon_size = configNumber("icon_size", 20),
    icon_color = tostring(configValue(severityName .. "_icon_color", severity.color)),
    icon_text_gap = configNumber("icon_text_gap", 10),
    line_gap = configNumber("line_gap", 2),
    padding_h = configNumber("content_padding_h", 0),
    padding_v = configNumber("content_padding_v", 0),
    max_text_width = configNumber("max_text_width", 0),
    summary_font_size = configNumber("summary_font_size", 14),
    summary_font_weight = tostring(configValue("summary_font_weight", "bold")),
    summary_color = tostring(configValue("summary_color", "on_surface")),
    body_font_size = configNumber("body_font_size", 12),
    body_color = tostring(configValue("body_color", "on_surface_variant")),
    text_align = tostring(configValue("text_align", "start")),
    two_line_balance = configNumber("two_line_balance", 2),
    content_fill = tostring(configValue("content_fill", "surface/0")),
    content_border = tostring(configValue("content_border", "outline/0")),
    content_border_width = configNumber("content_border_width", 0),
    content_radius = configNumber("content_radius", 0),
    timeout_ms = configNumber("default_timeout_ms", 4000),
  }

  applyProfileRules(style, payload)
  copyStyleValues(style, payload.style)
  if payload.timeout_ms ~= nil then
    style.timeout_ms = payload.timeout_ms
  end
  return style
end

local function onToastClick()
  if current ~= nil and current.command ~= nil and current.command ~= "" then
    noctalia.runAsync(current.command)
  end
  panel.close()
end

local function render()
  if current == nil then
    return
  end

  local style = currentStyle or resolvedStyle(current)
  local hasBody = current.body ~= nil and current.body ~= ""
  local textChildren = {
    ui.label({
      text = tostring(current.summary or ""),
      fontSize = style.summary_font_size,
      fontWeight = style.summary_font_weight,
      color = style.summary_color,
      textAlign = style.text_align,
      baseline = "inkCentered",
      maxWidth = style.max_text_width > 0 and style.max_text_width or nil,
      maxLines = 1,
    }),
  }
  if hasBody then
    table.insert(textChildren, ui.label({
      text = tostring(current.body),
      fontSize = style.body_font_size,
      color = style.body_color,
      textAlign = style.text_align,
      baseline = "inkCentered",
      maxWidth = style.max_text_width > 0 and style.max_text_width or nil,
      maxLines = 1,
    }))
  end

  local rowChildren = {}
  if style.show_icon then
    table.insert(rowChildren, ui.glyph({ name = style.icon, size = style.icon_size, color = style.icon_color }))
  end
  table.insert(rowChildren, ui.column({ gap = style.line_gap }, textChildren))

  local rootChildren = {
    ui.row({ gap = style.show_icon and style.icon_text_gap or 0, align = "center" }, rowChildren),
  }
  if hasBody and style.two_line_balance > 0 then
    table.insert(rootChildren, ui.spacer({ height = style.two_line_balance, flexGrow = 0 }))
  end

  -- The panel host removes its own card padding before laying out this tree.
  -- Fill that resulting content box instead of repeating the manifest's outer
  -- height here; justify/align then center the compact row in the real box.
  panel.render(ui.column({
    flexGrow = 1,
    justify = "center",
    align = "center",
    paddingH = style.padding_h,
    paddingV = style.padding_v,
    fill = style.content_fill,
    border = style.content_border,
    borderWidth = style.content_border_width,
    radius = style.content_radius,
    onClick = onToastClick,
  }, rootChildren))
end

function onOpen(context)
  local payload = noctalia.json.decode(context or "")
  if type(payload) ~= "table" or payload.summary == nil then
    current = { summary = tostring(context or "") }
  else
    current = payload
  end

  elapsedSeconds = 0
  currentStyle = resolvedStyle(current)
  local ms = tonumber(currentStyle.timeout_ms) or 4000
  timeoutSeconds = ms > 0 and math.max(1, math.ceil(ms / 1000)) or nil

  panel.setWantsSecondTicks(timeoutSeconds ~= nil)
  render()
end

function onClose()
  current = nil
  currentStyle = nil
end

function update()
  if timeoutSeconds == nil then
    return
  end
  elapsedSeconds += 1
  if elapsedSeconds >= timeoutSeconds then
    panel.close()
  end
end

-- `noctalia msg plugin pschmitt/osd:toast all dismiss <category>` — closes
-- the toast if it's currently showing that category (or any toast at all
-- when no category is given), mirroring pkgs/local/osd's `dismiss` verb.
function onIpc(event, payload)
  if event == "dismiss" and current ~= nil then
    if payload == nil or payload == "" or current.category == payload then
      panel.close()
    end
  end
end
