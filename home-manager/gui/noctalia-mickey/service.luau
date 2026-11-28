-- Mickey follows the control socket and emits "off" if it disconnects.
noctalia.state.set("mickey_input_away", false)
noctalia.runStream("@mickey@ status --waybar", function(line)
  local ok, status = pcall(noctalia.json.decode, line)
  noctalia.state.set("mickey_input_away", ok and type(status) == "table" and status.class == "remote")
end)
