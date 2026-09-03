--!nonstrict
-- Custom OSD toast — the [[panel]] entry. Opened with a JSON payload as
-- context:
--   noctalia msg panel-open pschmitt/osd:toast '{"summary":"...","body":"...","severity":"info","category":"...","command":"...","timeout_ms":4000}'
-- Only "summary" is required; everything else has a sane default. A plain
-- (non-JSON) context string is shown verbatim as the summary, so
-- `panel-open pschmitt/osd:toast "Hello"` also works for a quick one-liner.

local SEVERITY = {
  info = { glyph = "info-circle", color = "on_surface" },
  warn = { glyph = "alert-triangle", color = "secondary" },
  error = { glyph = "alert-circle", color = "error" },
}

local current = nil
local elapsedSeconds = 0
local timeoutSeconds = 4

local function onRowClick()
  if current ~= nil and current.command ~= nil and current.command ~= "" then
    noctalia.runAsync(current.command)
  end
  panel.close()
end

local function render()
  if current == nil then
    return
  end

  local sev = SEVERITY[current.severity] or SEVERITY.info
  local textChildren = {
    ui.label({ text = tostring(current.summary or ""), fontSize = 14, fontWeight = "bold" }),
  }
  if current.body ~= nil and current.body ~= "" then
    table.insert(textChildren, ui.label({ text = tostring(current.body), fontSize = 12, color = "on_surface_variant" }))
  end

  panel.render(ui.row({ gap = 10, align = "center", padding = 12, onClick = onRowClick }, {
    ui.glyph({ name = sev.glyph, size = 22, color = sev.color }),
    ui.column({ gap = 2, flexGrow = 1 }, textChildren),
  }))
end

function onOpen(context)
  local payload = noctalia.json.decode(context or "")
  if type(payload) ~= "table" or payload.summary == nil then
    current = { summary = tostring(context or "") }
  else
    current = payload
  end

  elapsedSeconds = 0
  local ms = tonumber(current.timeout_ms) or tonumber(noctalia.getConfig("default_timeout_ms")) or 4000
  timeoutSeconds = math.max(1, math.floor(ms / 1000))

  panel.setWantsSecondTicks(true)
  render()
end

function onClose()
  current = nil
end

function update()
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
