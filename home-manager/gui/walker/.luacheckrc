-- Elephant menu API globals (set/called by the elephant daemon)
globals = {
  "Name", "NamePretty", "Icon", "Terminal", "Cache", "FixedOrder", "Action", "SearchName",
  "Copy", "TogglePin", "GetEntries", "jsonDecode", "jsonEncode",
  "ActionDefault", "ActionToggle", "ActionUp", "ActionDown",
  "ActionPin", "ActionCopy", "ActionOpen", "ActionRefresh", "ActionSetTemp", "ActionSetBrightness",
  "ActionSetFanSpeed",
}

-- Elephant calls these functions with fixed (value, args, query) signatures;
-- the last two are unused here but must be accepted.
unused_args = false
