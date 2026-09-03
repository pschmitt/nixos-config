--!nonstrict
-- Timewarrior panel — week/month/year totals + this week's daily
-- breakdown, ported from the DMS TimewarriorWidget.qml popoutContent.

local summary = noctalia.state.get("tw_summary") or { week = "0:00", month = "0:00", year = "0:00", days = {} }

local function statBox(label, value)
  return ui.column({
    flexGrow = 1,
    gap = 2,
    align = "center",
    padding = 10,
    fill = "surface_variant",
    radius = 8,
  }, {
    ui.label({ text = value, fontSize = 18, fontWeight = "bold" }),
    ui.label({ text = label, fontSize = 12, color = "on_surface_variant" }),
  })
end

local function dayRow(day)
  return ui.row({ justify = "space_between", padding = 2 }, {
    ui.label({ text = (day.dow or "") .. " " .. (day.date or ""), color = "on_surface_variant", fontSize = 13 }),
    ui.label({ text = day.duration or "", fontSize = 13 }),
  })
end

local function render()
  local content = {
    ui.label({ text = "Timewarrior", fontSize = 16, fontWeight = "bold" }),
    ui.row({ gap = 8 }, {
      statBox("Week", summary.week),
      statBox("Month", summary.month),
      statBox("Year", summary.year),
    }),
    ui.separator({}),
    ui.label({ text = "This week", fontSize = 14, fontWeight = "bold" }),
  }

  local days = summary.days or {}
  if #days > 0 then
    local rows = {}
    for _, day in ipairs(days) do
      table.insert(rows, dayRow(day))
    end
    table.insert(content, ui.scroll({ flexGrow = 1, gap = 4 }, rows))
  else
    table.insert(content, ui.label({ text = "No tracked time this week", color = "on_surface_variant", fontSize = 13 }))
  end

  panel.render(ui.column({ gap = 8, padding = 12 }, content))
end

noctalia.state.watch("tw_summary", function(val)
  if type(val) == "table" then
    summary = val
    render()
  end
end)

render()
