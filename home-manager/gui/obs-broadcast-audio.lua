obs = obslua

local runtime = os.getenv("XDG_RUNTIME_DIR")
local directory = runtime and (runtime .. "/obs-broadcast-audio")
local scenes = {
  ARD = { ["ARD Live"] = true },
  ZDF = { ["ZDF Live"] = true },
  Tagesschau = { Browser = true, Media = true },
}
local saved = {}
local device_name, device_id
local engaged = false
local error_message = ""

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

local function publish(routing)
  if not directory then return end
  local file = io.open(directory .. "/status.new", "w")
  if not file then return end
  file:write(tostring(os.time()), "\n", engaged and "enabled" or "disabled", "\n",
    routing and "routing" or "silent", "\n", error_message, "\n")
  file:close()
  os.rename(directory .. "/status.new", directory .. "/status")
end

local function each_source(callback)
  local sources = obs.obs_enum_sources()
  local ok, err = pcall(function()
    for _, source in ipairs(sources or {}) do callback(source) end
  end)
  obs.source_list_release(sources)
  if not ok then error(err) end
end

local function release()
  for uuid, entry in pairs(saved) do
    obs.obs_source_set_monitoring_type(entry.source, entry.monitoring)
    obs.obs_source_release(entry.source)
    saved[uuid] = nil
  end
  if engaged then
    obs.obs_set_audio_monitoring_device(device_name, device_id)
    engaged = false
  end
end

local function engage()
  local conflict = false
  each_source(function(source)
    if obs.obs_source_get_monitoring_type(source) ~= obs.OBS_MONITORING_TYPE_NONE then
      conflict = true
    end
  end)
  if conflict then
    error("An OBS source already has monitoring enabled.")
  end
  local profile = obs.obs_frontend_get_profile_config()
  device_name = obs.config_get_string(profile, "Audio", "MonitoringDeviceName") or "Default"
  device_id = obs.config_get_string(profile, "Audio", "MonitoringDeviceId") or "default"
  if not obs.obs_set_audio_monitoring_device("OBS Broadcast", "obs_broadcast") then
    error("Could not select the OBS Broadcast monitoring device.")
  end
  engaged = true
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
    if not ok then error(err) end
  elseif allowed[obs.obs_source_get_name(source)] then
    local kind = obs.obs_source_get_unversioned_id(source)
    if kind == "ffmpeg_source" or kind == "browser_source" then
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

local function reconcile()
  if not requested() then
    error_message = ""
    release()
    publish(false)
    return
  end
  if not engaged then engage() end
  local selected = {}
  local current = obs.obs_frontend_get_current_scene()
  if current then
    local ok, err = pcall(function()
      local allowed = scenes[obs.obs_source_get_name(current)]
      if allowed and not transitioning() then collect(current, allowed, selected, {}) end
    end)
    obs.obs_source_release(current)
    if not ok then error(err) end
  end
  each_source(function(source)
    local uuid = obs.obs_source_get_uuid(source)
    if saved[uuid] == nil
        and obs.obs_source_get_monitoring_type(source) ~= obs.OBS_MONITORING_TYPE_NONE then
      error("Another OBS source enabled monitoring; audio sharing stopped.")
    end
  end)
  local routing = false
  each_source(function(source)
    local uuid = obs.obs_source_get_uuid(source)
    if selected[uuid] and saved[uuid] == nil then
      saved[uuid] = {
        source = obs.obs_source_get_ref(source),
        monitoring = obs.obs_source_get_monitoring_type(source),
      }
    end
  end)
  for uuid, entry in pairs(saved) do
    local monitoring = obs.OBS_MONITORING_TYPE_NONE
    if selected[uuid] then
      monitoring = obs.OBS_MONITORING_TYPE_MONITOR_AND_OUTPUT
      routing = true
    end
    if obs.obs_source_get_monitoring_type(entry.source) ~= monitoring then
      obs.obs_source_set_monitoring_type(entry.source, monitoring)
    end
  end
  publish(routing)
end

function tick()
  local ok, err = pcall(reconcile)
  if not ok then
    disarm()
    local released, release_error = pcall(release)
    error_message = "OBS audio sharing stopped: " .. tostring(err):gsub("[\r\n]", " ")
    if not released then
      obs.script_log(obs.LOG_ERROR, "Audio cleanup failed: " .. tostring(release_error))
    end
    publish(false)
  end
end

function frontend_event(event)
  if event == obs.OBS_FRONTEND_EVENT_SCENE_COLLECTION_CHANGING
      or event == obs.OBS_FRONTEND_EVENT_PROFILE_CHANGING
      or event == obs.OBS_FRONTEND_EVENT_EXIT then
    disarm()
  end
  tick()
end

function script_description()
  return "Optional ARD / ZDF / Tagesschau audio into Meeting Microphone. " ..
    "Run obs-broadcast-audio on|off|toggle|status. Off by default; " ..
    "only allowlisted visible media/browser sources on the program scene are monitored. " ..
    "Existing monitoring must be disabled before enabling this feature."
end

function script_load(_settings)
  error_message = ""
  obs.obs_frontend_add_event_callback(frontend_event)
  obs.timer_add(tick, 100)
end

function script_unload()
  obs.timer_remove(tick)
  obs.obs_frontend_remove_event_callback(frontend_event)
  disarm()
  tick()
end
