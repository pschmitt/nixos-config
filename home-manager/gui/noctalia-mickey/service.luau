-- Mickey follows the control socket and emits "off" if it disconnects.
noctalia.state.set("mickey_input_state", "local")
noctalia.runStream("@mickey@ status --waybar", function(line)
  local ok, status = pcall(noctalia.json.decode, line)
  local state = "local"
  if ok and type(status) == "table" then
    if status.class == "remote" then
      state = "recallable"
    elseif status.class == "local" and status.away == true then
      state = "away"
    end
  end
  noctalia.state.set("mickey_input_state", state)
end)
