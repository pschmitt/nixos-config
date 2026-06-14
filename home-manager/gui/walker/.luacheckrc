-- Elephant menu API globals (set/called by the elephant daemon)
globals = {
  "Name", "NamePretty", "Icon", "Terminal", "Cache", "FixedOrder", "Action",
  "Copy", "TogglePin", "GetEntries",
}

-- Elephant calls these functions with fixed (value, args, query) signatures;
-- the last two are unused here but must be accepted.
unused_args = false
