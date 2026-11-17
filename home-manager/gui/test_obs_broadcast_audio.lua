local path = assert(arg[1])
local directory = assert(os.getenv("XDG_RUNTIME_DIR")) .. "/obs-broadcast-audio"
local current, device, progress = "Webcam", "default", 1
local media = { name = "ARD Live", kind = "ffmpeg_source", monitoring = 0 }
local browser = { name = "Browser", kind = "browser_source", monitoring = 0 }
local mic = { name = "mic", kind = "pulse_input_capture", monitoring = 0 }
local sources = { media, browser, mic }
local program = {
  Webcam = { name = "Webcam", items = { { source = mic, visible = true } } },
  ARD = { name = "ARD", items = { { source = media, visible = true } } },
  Tagesschau = { name = "Tagesschau", items = { { source = browser, visible = true } } },
}

obslua = {
  OBS_MONITORING_TYPE_NONE = 0,
  OBS_MONITORING_TYPE_MONITOR_AND_OUTPUT = 2,
  OBS_FRONTEND_EVENT_SCENE_CHANGED = 1,
  OBS_FRONTEND_EVENT_TRANSITION_STOPPED = 2,
  OBS_FRONTEND_EVENT_SCENE_COLLECTION_CHANGING = 3,
  OBS_FRONTEND_EVENT_PROFILE_CHANGING = 4,
  OBS_FRONTEND_EVENT_EXIT = 5,
  obs_enum_sources = function() return sources end,
  source_list_release = function() end,
  obs_source_get_name = function(s) return s.name end,
  obs_source_get_uuid = function(s) return tostring(s) end,
  obs_source_get_ref = function(s) return s end,
  obs_source_get_monitoring_type = function(s) return s.monitoring end,
  obs_source_set_monitoring_type = function(s, v) s.monitoring = v end,
  obs_source_get_unversioned_id = function(s) return s.kind end,
  obs_frontend_get_profile_config = function() return {} end,
  config_get_string = function() return "default" end,
  obs_set_audio_monitoring_device = function(_, id) device = id; return true end,
  obs_frontend_get_current_scene = function() return program[current] end,
  obs_scene_from_source = function(s) return s.items and s end,
  obs_group_from_source = function() return nil end,
  obs_scene_enum_items = function(s) return s.items end,
  obs_sceneitem_visible = function(i) return i.visible end,
  obs_sceneitem_get_source = function(i) return i.source end,
  sceneitem_list_release = function() end,
  obs_source_release = function() end,
  obs_get_source_by_name = function(name)
    for _, s in ipairs(sources) do if s.name == name then return s end end
  end,
  obs_frontend_get_current_transition = function() return {} end,
  obs_transition_get_time = function() return progress end,
  script_log = function() end,
  timer_remove = function() end,
  obs_frontend_remove_event_callback = function() end,
}

dofile(path)
local function request(enabled)
  if enabled then
    local f = assert(io.open(directory .. "/requested", "w")); f:close()
  else
    os.remove(directory .. "/requested")
  end
end

request(false)
tick()
assert(device == "default" and media.monitoring == 0, "default must be off")
request(true)
tick()
assert(device == "obs_broadcast" and media.monitoring == 0, "webcam must stay silent")
current = "ARD"
tick()
assert(media.monitoring == 2 and mic.monitoring == 0, "only broadcast source is monitored")
current = "Tagesschau"
tick()
assert(media.monitoring == 0 and browser.monitoring == 2, "switch replaces monitored source")
program.Tagesschau.items[1].visible = false
tick()
assert(browser.monitoring == 0, "hidden source must stay silent")
program.Tagesschau.items[1].visible = true
progress = 0.5
frontend_event(obslua.OBS_FRONTEND_EVENT_SCENE_CHANGED)
assert(browser.monitoring == 0, "transition must be silent")
progress = 1
tick()
assert(browser.monitoring == 2, "route resumes after transition")
current = "Webcam"
tick()
assert(browser.monitoring == 0 and media.monitoring == 0, "switch away must be silent")
request(false)
tick()
assert(device == "default", "monitoring device must be restored")
mic.monitoring = 2
request(true)
tick()
assert(device == "default" and media.monitoring == 0, "existing monitoring must refuse enable")
mic.monitoring = 0
request(true)
tick()
current = "ARD"
tick()
assert(media.monitoring == 2)
frontend_event(obslua.OBS_FRONTEND_EVENT_PROFILE_CHANGING)
assert(media.monitoring == 0 and device == "default", "profile switch disarms route")
request(true)
tick()
script_unload()
assert(media.monitoring == 0 and device == "default", "unload restores state")
request(true)
tick()
media.name = "Renamed broadcast"
request(false)
tick()
assert(media.monitoring == 0 and device == "default", "rename must not break cleanup")
media.name = "ARD Live"
request(true)
tick()
local get_name = obslua.obs_source_get_name
obslua.obs_source_get_name = function() error("injected failure") end
tick()
assert(media.monitoring == 0 and device == "default", "Lua failure must restore monitoring")
obslua.obs_source_get_name = get_name
current = "Webcam"
request(true)
tick()
media.monitoring = 2
current = "ARD"
tick()
assert(device == "default", "newly selected monitored source must disarm sharing")
media.monitoring = 0
print("Lua routing tests passed: default off, allowlist, visibility, transitions, conflicts, lifecycle, rename, errors")
