obs = obslua

local runtime = os.getenv("XDG_RUNTIME_DIR")
local directory = runtime and (runtime .. "/obs-broadcast-audio")
-- Program scene -> broadcast sources that may be routed while it is on air.
local scenes = {
  ARD = { ["ARD Live"] = true },
  ZDF = { ["ZDF Live"] = true },
  Tagesschau = { Browser = true, Media = true },
}
local kinds = { ffmpeg_source = true, browser_source = true }
-- Every source of this feature, whatever scene it is in. While sharing is on
-- the script owns all of them: it remembers their monitoring mode and keeps
-- each silent unless it is the one routed source.
local intended = {}
for _, names in pairs(scenes) do
  for name in pairs(names) do intended[name] = true end
end

local NONE = obs.OBS_MONITORING_TYPE_NONE
local BOTH = obs.OBS_MONITORING_TYPE_MONITOR_AND_OUTPUT

-- uuid -> { source = held reference, monitoring = mode before we took over }
local owned = {}
local device_name, device_id
-- True from the moment the global monitoring device may differ from the
-- original until the original is back in place.
local engaged = false
local error_message, error_time = "", 0
-- OBS calls frontend_event synchronously from inside its own API (scene,
-- monitoring and device changes). tick() therefore never nests: a nested call
-- only asks for one more pass once the running one is done.
local busy, dirty = false, false
-- Set by a lifecycle event or unload that arrives while a pass is running: the
-- pass stops at its next checkpoint and the route is released.
local abort, unloaded = false, false
local STOP = {}
local last_log, last_log_time = nil, 0
local ERROR_VISIBLE_SECONDS = 2

local function log(message)
  local now = os.time()
  if message == last_log and now - last_log_time < 60 then return end
  last_log, last_log_time = message, now
  obs.script_log(obs.LOG_WARNING, message)
end

local function refuse(message)
  error({ refusal = message })
end

local function checkpoint()
  if abort or unloaded then error(STOP) end
end

local function requested()
  if not directory then return false end
  local file = io.open(directory .. "/requested", "r")
  if not file then return false end
  file:close()
  return true
end

local function disarm()
  if directory then os.remove(directory .. "/requested") end
end

local function publish(routing, enabled)
  if not directory then return end
  if error_message ~= "" and os.time() - error_time >= ERROR_VISIBLE_SECONDS then
    error_message = ""
  end
  local file = io.open(directory .. "/status.new", "w")
  if not file then return end
  file:write(tostring(os.time()), "\n", enabled and "enabled" or "disabled", "\n",
    routing and "routing" or "silent", "\n", error_message, "\n")
  file:close()
  os.rename(directory .. "/status.new", directory .. "/status")
end

-- One pass over all sources. The enumeration is plain data: nothing in the
-- loop calls back into OBS to change state, so a failure cannot leave a half
-- finished mutation behind and the list is always released.
--  * intended sources that are not owned yet are adopted (prior mode saved)
--  * the first source outside the feature that is monitored is reported
local function scan()
  local sources = obs.obs_enum_sources()
  local seen, foreign = {}, nil
  local ok, err = pcall(function()
    for _, source in ipairs(sources or {}) do
      local uuid = obs.obs_source_get_uuid(source)
      seen[uuid] = true
      if not owned[uuid] then
        local name = obs.obs_source_get_name(source)
        local mode = obs.obs_source_get_monitoring_type(source)
        if intended[name] and kinds[obs.obs_source_get_unversioned_id(source)] then
          local held = obs.obs_source_get_ref(source)
          if held then owned[uuid] = { source = held, monitoring = mode } end
        elseif mode ~= NONE and not foreign then
          foreign = tostring(name):sub(1, 60)
        end
      end
    end
  end)
  obs.source_list_release(sources)
  if not ok then error(err, 0) end
  return seen, foreign
end

-- Sources that left OBS (deleted or replaced) are dropped together with their
-- reference; a replacement with the same name is adopted by the next scan.
local function forget(seen)
  for uuid, entry in pairs(owned) do
    if not seen[uuid] then
      pcall(obs.obs_source_set_monitoring_type, entry.source, NONE)
      pcall(obs.obs_source_release, entry.source)
      owned[uuid] = nil
    end
  end
end

local function silence_all()
  for _, entry in pairs(owned) do
    if obs.obs_source_get_monitoring_type(entry.source) ~= NONE then
      obs.obs_source_set_monitoring_type(entry.source, NONE)
    end
  end
end

-- Teardown order matters: nothing may be audible while OBS Broadcast is still
-- the monitoring device, so every owned source is silenced first, then the
-- original device returns, and only then the original modes come back.
-- Returns false if the device could not be restored; the sources stay owned
-- and silent so the next pass retries.
local function release()
  if engaged then
    for _, entry in pairs(owned) do
      pcall(function()
        if obs.obs_source_get_monitoring_type(entry.source) ~= NONE then
          obs.obs_source_set_monitoring_type(entry.source, NONE)
        end
      end)
    end
    local ok, result = pcall(obs.obs_set_audio_monitoring_device, device_name, device_id)
    if ok and result ~= false then engaged = false end
  end
  if engaged then return false end
  for uuid, entry in pairs(owned) do
    pcall(function()
      if obs.obs_source_get_monitoring_type(entry.source) ~= entry.monitoring then
        obs.obs_source_set_monitoring_type(entry.source, entry.monitoring)
      end
    end)
    pcall(obs.obs_source_release, entry.source)
    owned[uuid] = nil
  end
  return true
end

local function engage()
  error_message = ""
  local _, foreign = scan()
  if foreign then
    refuse("An unrelated OBS source has monitoring enabled (" .. foreign
      .. "); audio sharing was not started.")
  end
  -- Prior modes are saved (by scan) and the sources silent before the global
  -- device changes, so no source can reach the sink even for an instant.
  silence_all()
  checkpoint()
  local profile = obs.obs_frontend_get_profile_config()
  device_name = obs.config_get_string(profile, "Audio", "MonitoringDeviceName") or "Default"
  device_id = obs.config_get_string(profile, "Audio", "MonitoringDeviceId") or "default"
  engaged = true
  if obs.obs_set_audio_monitoring_device("OBS Broadcast", "obs_broadcast") == false then
    refuse("Could not select the OBS Broadcast monitoring device.")
  end
  checkpoint()
end

local function collect(source, allowed, selected, visited)
  local uuid = obs.obs_source_get_uuid(source)
  if visited[uuid] then return end
  visited[uuid] = true
  local scene = obs.obs_scene_from_source(source)
  if not scene then scene = obs.obs_group_from_source(source) end
  if scene then
    local items = obs.obs_scene_enum_items(scene)
    local ok, err = pcall(function()
      for _, item in ipairs(items or {}) do
        if obs.obs_sceneitem_visible(item) then
          collect(obs.obs_sceneitem_get_source(item), allowed, selected, visited)
        end
      end
    end)
    obs.sceneitem_list_release(items)
    if not ok then error(err, 0) end
  elseif allowed[obs.obs_source_get_name(source)] then
    local kind = obs.obs_source_get_unversioned_id(source)
    if kinds[kind] then
      selected[uuid] = true
    end
  end
end

local function transitioning()
  local transition = obs.obs_frontend_get_current_transition()
  if not transition then return false end
  local progress = obs.obs_transition_get_time(transition)
  obs.obs_source_release(transition)
  return progress > 0 and progress < 1
end

local function select_program()
  local selected = {}
  local current = obs.obs_frontend_get_current_scene()
  if current then
    local ok, err = pcall(function()
      local allowed = scenes[obs.obs_source_get_name(current)]
      if allowed and not transitioning() then collect(current, allowed, selected, {}) end
    end)
    obs.obs_source_release(current)
    if not ok then error(err, 0) end
  end
  return selected
end

local function reconcile()
  if not requested() then
    if engaged or next(owned) ~= nil then
      if not release() then
        log("Could not restore the OBS monitoring device; sources stay silent, retrying.")
      end
    end
    publish(false, false)
    return
  end
  if not engaged then
    engage()
  else
    local seen, foreign = scan()
    forget(seen)
    if foreign then
      refuse("An unrelated OBS source enabled monitoring (" .. foreign
        .. "); audio sharing stopped.")
    end
  end
  checkpoint()
  local selected = select_program()
  checkpoint()
  -- Silence first, then enable: a switch never overlaps two broadcasts.
  for uuid, entry in pairs(owned) do
    if not selected[uuid]
        and obs.obs_source_get_monitoring_type(entry.source) ~= NONE then
      obs.obs_source_set_monitoring_type(entry.source, NONE)
    end
  end
  local routing = false
  for uuid, entry in pairs(owned) do
    if selected[uuid] then
      checkpoint()
      if obs.obs_source_get_monitoring_type(entry.source) ~= BOTH then
        obs.obs_source_set_monitoring_type(entry.source, BOTH)
      end
      routing = obs.obs_source_get_monitoring_type(entry.source) == BOTH
    end
  end
  publish(routing, true)
end

local function with_trace(err)
  if type(err) == "table" then return err end
  local trace = debug and debug.traceback and debug.traceback("", 2) or ""
  return { message = tostring(err), trace = trace }
end

-- One-shot failure: disarm, silence and restore, say so once. The request is
-- gone afterwards, so later passes only release (nothing) and never fail again.
local function stop_on(problem)
  if problem == STOP then
    if not release() then log("Could not restore the OBS monitoring device; retrying.") end
    publish(false, false)
    return
  end
  disarm()
  local message = problem.refusal or problem.message or "unknown error"
  message = (tostring(message):gsub("%s+", " "))
  local restored = release()
  error_message = "OBS audio sharing stopped: " .. message
  error_time = os.time()
  log("[audio sharing stopped] " .. message
    .. (problem.trace and ("\n" .. problem.trace) or ""))
  if not restored then log("Could not restore the OBS monitoring device; retrying.") end
  publish(false, false)
end

function tick()
  if busy then
    dirty = true
    return
  end
  if unloaded then return end
  busy = true
  local ok, err = pcall(function()
    local passes = 0
    repeat
      dirty, abort = false, false
      passes = passes + 1
      local fine, problem = xpcall(reconcile, with_trace)
      if not fine then stop_on(problem) end
    until not dirty or passes >= 3
  end)
  busy = false
  if not ok then
    pcall(disarm)
    pcall(release)
    log("Unexpected failure, audio sharing stopped: " .. tostring(err))
  end
end

function frontend_event(event)
  if event == obs.OBS_FRONTEND_EVENT_SCENE_COLLECTION_CHANGING
      or event == obs.OBS_FRONTEND_EVENT_PROFILE_CHANGING
      or event == obs.OBS_FRONTEND_EVENT_EXIT then
    disarm()
    abort = true
  end
  tick()
end

function script_description()
  return "Optional ARD / ZDF / Tagesschau audio into Meeting Microphone. " ..
    "Run obs-broadcast-audio on|off|toggle|status. Off by default; " ..
    "only allowlisted visible media/browser sources on the program scene are monitored. " ..
    "While on, the ARD/ZDF/Tagesschau sources are owned by the script (their monitoring " ..
    "modes are restored afterwards); monitoring on any other source must be disabled first."
end

function script_load(_settings)
  error_message = ""
  unloaded = false
  obs.obs_frontend_add_event_callback(frontend_event)
  obs.timer_add(tick, 100)
end

function script_unload()
  unloaded, abort = true, true
  obs.timer_remove(tick)
  obs.obs_frontend_remove_event_callback(frontend_event)
  disarm()
  pcall(release)
  pcall(publish, false, false)
end
