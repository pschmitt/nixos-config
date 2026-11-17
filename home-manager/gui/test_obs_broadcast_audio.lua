-- Mock of the OBS Lua API: enough fidelity to catch spills, leaks and
-- reentrancy. OBS calls frontend callbacks synchronously from inside its own
-- API; the hooks below reproduce that.
local path = assert(arg[1])
local directory = assert(os.getenv("XDG_RUNTIME_DIR")) .. "/obs-broadcast-audio"
os.execute("mkdir -p '" .. directory .. "'")

local NONE, ONLY, BOTH = 0, 1, 2
local EV = { SCENE_CHANGED = 1, TRANSITION_STOPPED = 2, COLLECTION = 3, PROFILE = 4, EXIT = 5 }

local W -- world of the running scenario

local function request(enabled)
  if enabled then
    local f = assert(io.open(directory .. "/requested", "w")); f:close()
  else
    os.remove(directory .. "/requested")
  end
end

local function status()
  local f = io.open(directory .. "/status")
  if not f then return nil end
  local lines = {}
  for line in f:lines() do lines[#lines + 1] = line end
  f:close()
  return { enabled = lines[2] == "enabled", routing = lines[3] == "routing", error = lines[4] or "" }
end

local function new_source(name, kind, monitoring)
  W.counter = W.counter + 1
  return { name = name, kind = kind, monitoring = monitoring or NONE, refs = 0,
    uuid = "uuid-" .. W.counter }
end

-- The sources the script may route in the current program scene, as the
-- test's own oracle (independent of the script's logic).
local function audible_ok(s)
  if W.progress ~= 1 then return false end
  local f = io.open(directory .. "/requested"); if not f then return false end; f:close()
  local scene = W.program[W.current]
  for _, item in ipairs(scene.items) do
    if item.visible and item.source == s and scene.allow and scene.allow[s.name] then return true end
  end
  return false
end

local function spill(what, s)
  W.violations[#W.violations + 1] = what .. ": " .. s.name
end

-- While sharing is requested every broadcast source must be silent or heard
-- only through the OBS Broadcast sink and only while it is on the program
-- scene. Anything else is audible on the user's own output, or is a tail of a
-- source that already left the program, so it is a wrong-sink transient.
local function sharing_requested()
  local f = io.open(directory .. "/requested")
  if not f then return false end
  f:close()
  return true
end

local function invariant(what)
  if not W.watch or not sharing_requested() then return end
  for _, s in ipairs({ W.ard, W.zdf, W.browser }) do
    if s.monitoring ~= NONE then
      if W.device ~= "obs_broadcast" then
        spill(what .. " audible on the user's output", s)
      elseif not audible_ok(s) then
        spill(what .. " tail on the broadcast sink", s)
      end
    end
  end
end

local function setup()
  W = { counter = 0, current = "Webcam", device = "default", progress = 1, calls = 0,
    violations = {}, logs = {}, device_sets = 0, device_ok = true, hooks = {} }
  W.ard = new_source("ARD Live", "ffmpeg_source")
  W.zdf = new_source("ZDF Live", "ffmpeg_source")
  W.browser = new_source("Browser", "browser_source")
  W.mic = new_source("mic", "pulse_input_capture")
  W.desktop = new_source("Desktop Audio", "pulse_output_capture")
  W.sources = { W.ard, W.zdf, W.browser, W.mic, W.desktop }
  W.program = {
    Webcam = { name = "Webcam", items = { { source = W.mic, visible = true } } },
    ARD = { name = "ARD", allow = { ["ARD Live"] = true }, items = { { source = W.ard, visible = true } } },
    ZDF = { name = "ZDF", allow = { ["ZDF Live"] = true }, items = { { source = W.zdf, visible = true } } },
    Tagesschau = { name = "Tagesschau", allow = { Browser = true, Media = true },
      items = { { source = W.browser, visible = true } } },
  }
  for key, scene in pairs(W.program) do scene.uuid = "scene-" .. key; scene.refs = 0 end
  local function count() W.calls = W.calls + 1 end
  local function hook(name) if W.hooks[name] then W.hooks[name]() end end
  obslua = {
    OBS_MONITORING_TYPE_NONE = NONE,
    OBS_MONITORING_TYPE_MONITOR_AND_OUTPUT = BOTH,
    OBS_FRONTEND_EVENT_SCENE_CHANGED = EV.SCENE_CHANGED,
    OBS_FRONTEND_EVENT_TRANSITION_STOPPED = EV.TRANSITION_STOPPED,
    OBS_FRONTEND_EVENT_SCENE_COLLECTION_CHANGING = EV.COLLECTION,
    OBS_FRONTEND_EVENT_PROFILE_CHANGING = EV.PROFILE,
    OBS_FRONTEND_EVENT_EXIT = EV.EXIT,
    LOG_WARNING = 300, LOG_ERROR = 400,
    obs_enum_sources = function()
      count()
      local list = {}
      for i, s in ipairs(W.sources) do list[i] = s; s.refs = s.refs + 1 end
      return list
    end,
    source_list_release = function(list) count(); for _, s in ipairs(list) do s.refs = s.refs - 1 end end,
    obs_source_get_name = function(s) count(); return s.name end,
    obs_source_get_uuid = function(s) count(); return s.uuid end,
    obs_source_get_ref = function(s) count(); s.refs = s.refs + 1; return s end,
    obs_source_release = function(s) count(); s.refs = s.refs - 1 end,
    obs_source_get_monitoring_type = function(s) count(); return s.monitoring end,
    obs_source_set_monitoring_type = function(s, v)
      count()
      if v ~= NONE and W.device == "obs_broadcast" and not audible_ok(s) then spill("enabled on sink", s) end
      s.monitoring = v
      invariant("monitoring change")
      hook("set_monitoring")
    end,
    obs_source_get_unversioned_id = function(s) count(); return s.kind end,
    obs_frontend_get_profile_config = function() count(); return {} end,
    config_get_string = function() count(); return "default" end,
    obs_set_audio_monitoring_device = function(_, id)
      count()
      W.device_sets = W.device_sets + 1
      if W.device_ok == false and id == "default" then return false end
      if id == "obs_broadcast" then
        for _, s in ipairs(W.sources) do
          if s.monitoring ~= NONE and not audible_ok(s) then spill("on sink at switch", s) end
        end
      end
      if W.device == "obs_broadcast" and id ~= "obs_broadcast" then
        -- The original device returns only once nothing can reach it.
        for _, s in ipairs({ W.ard, W.zdf, W.browser }) do
          if s.monitoring ~= NONE then spill("device restored under a source tail", s) end
        end
      end
      W.device = id
      invariant("device change")
      hook("set_device")
      return true
    end,
    obs_frontend_get_current_scene = function()
      count(); local s = W.program[W.current]; s.refs = (s.refs or 0) + 1; return s
    end,
    obs_scene_from_source = function(s) count(); return s.items and s end,
    obs_group_from_source = function() count(); return nil end,
    obs_scene_enum_items = function(s) count(); return s.items end,
    obs_sceneitem_visible = function(i) count(); return i.visible end,
    obs_sceneitem_get_source = function(i) count(); return i.source end,
    sceneitem_list_release = function() count() end,
    obs_frontend_get_current_transition = function() count(); return { refs = 0 } end,
    obs_transition_get_time = function() count(); return W.progress end,
    script_log = function(_, message) W.logs[#W.logs + 1] = message end,
    timer_add = function() end,
    timer_remove = function() end,
    obs_frontend_add_event_callback = function() end,
    obs_frontend_remove_event_callback = function() end,
  }
  dofile(path)
  script_load({})
end

local function leaks()
  for _, s in ipairs(W.sources) do
    if s.refs ~= 0 then return s.name .. " refs=" .. s.refs end
  end
  for _, s in pairs(W.program) do
    if (s.refs or 0) ~= 0 then return s.name .. " refs=" .. s.refs end
  end
end

local function check_clean(label)
  assert(#W.violations == 0, label .. ": spill " .. table.concat(W.violations, "; "))
  local leaked = leaks()
  assert(leaked == nil, label .. ": leaked reference " .. tostring(leaked))
end

-- Reentrancy hook: OBS fires a scene event and a timer tick inside the call.
-- The nested tick must not run another pass (no OBS call at all).
local function reentrant(depth_counter)
  return function()
    depth_counter.n = depth_counter.n + 1
    local before = W.calls
    frontend_event(EV.SCENE_CHANGED)
    tick()
    assert(W.calls == before, "nested tick re-entered OBS")
  end
end

local function off_and_assert_restored(label, device)
  request(false)
  tick()
  assert(W.device == (device or "default"), label .. ": device not restored")
  check_clean(label)
end

-- 1. Off by default, nothing touched.
setup()
request(false)
tick()
assert(W.device == "default" and W.device_sets == 0, "default must be off")
assert(W.ard.monitoring == NONE and not status().enabled and not status().routing)
check_clean("idle")

-- 2. Pre-existing modes on the broadcast sources are accepted, owned, silenced
--    before the device switch, and restored exactly (different modes).
setup()
W.ard.monitoring, W.zdf.monitoring, W.browser.monitoring = BOTH, ONLY, BOTH
request(true)
tick()
assert(W.device == "obs_broadcast", "route must engage with pre-existing broadcast modes")
assert(W.ard.monitoring == NONE and W.zdf.monitoring == NONE and W.browser.monitoring == NONE,
  "webcam scene: every broadcast source silent")
assert(status().enabled and not status().routing and status().error == "")
W.current = "ARD"
tick()
assert(W.ard.monitoring == BOTH and W.zdf.monitoring == NONE, "only the program source is routed")
assert(status().routing)
W.current = "ZDF"
tick()
assert(W.ard.monitoring == NONE and W.zdf.monitoring == BOTH, "switch moves the route")
W.program.ZDF.items[1].visible = false
tick()
assert(W.zdf.monitoring == NONE and not status().routing, "hidden source silent")
W.program.ZDF.items[1].visible = true
W.progress = 0.5
frontend_event(EV.SCENE_CHANGED)
assert(W.zdf.monitoring == NONE, "transition silent")
W.progress = 1
tick()
assert(W.zdf.monitoring == BOTH, "route resumes after transition")
W.current = "Tagesschau"
tick()
assert(W.zdf.monitoring == NONE and W.browser.monitoring == BOTH)
W.current = "Webcam"
tick()
assert(W.browser.monitoring == NONE and W.ard.monitoring == NONE)
W.current = "ARD"
tick()
off_and_assert_restored("off restores")
assert(W.ard.monitoring == BOTH and W.zdf.monitoring == ONLY and W.browser.monitoring == BOTH,
  "exact prior modes restored")
assert(not status().enabled)
-- second toggle works from the restored state
request(true)
tick()
assert(W.device == "obs_broadcast" and W.ard.monitoring == BOTH and W.zdf.monitoring == NONE)
off_and_assert_restored("second toggle")
assert(W.zdf.monitoring == ONLY)

-- 3. Unrelated monitoring is refused before the device or any source changes.
setup()
W.ard.monitoring, W.zdf.monitoring = BOTH, BOTH
W.desktop.monitoring = ONLY
request(true)
tick()
assert(W.device == "default" and W.device_sets == 0, "device must not be touched")
assert(W.ard.monitoring == BOTH and W.zdf.monitoring == BOTH and W.desktop.monitoring == ONLY,
  "no mode may be modified by a refused enable")
assert(not io.open(directory .. "/requested"), "refusal disarms")
assert(status().error:find("unrelated OBS source") and status().error:find("Desktop Audio"))
assert(not status().enabled)
for _ = 1, 50 do tick() end
assert(#W.logs == 1, "a refusal logs exactly once, got " .. #W.logs)
assert(W.ard.monitoring == BOTH, "still untouched")
check_clean("refusal")

-- 3b. A monitored source of the right name but the wrong kind is unrelated.
setup()
local vlc = new_source("Media", "vlc_source", BOTH)
W.sources[#W.sources + 1] = vlc
request(true)
tick()
assert(W.device == "default" and vlc.monitoring == BOTH and not status().enabled)
vlc.refs = 0
check_clean("wrong kind")

-- 4. Unrelated monitoring appearing while routing stops it, restoring everything.
setup()
W.ard.monitoring = BOTH
request(true)
W.current = "ARD"
tick()
assert(W.ard.monitoring == BOTH and W.device == "obs_broadcast")
W.mic.monitoring = BOTH
tick()
assert(W.device == "default" and W.ard.monitoring == BOTH, "restored after conflict")
assert(status().error:find("enabled monitoring") and not status().enabled)
for _ = 1, 30 do tick() end
assert(#W.logs == 1, "conflict is logged once")
assert(not io.open(directory .. "/requested"))
check_clean("late conflict")

-- 5. Reentrancy: scene events and ticks fire inside every set call.
setup()
W.ard.monitoring, W.zdf.monitoring = BOTH, BOTH
local depth = { n = 0 }
W.hooks.set_monitoring = reentrant(depth)
W.hooks.set_device = reentrant(depth)
request(true)
tick()
W.current = "ARD"
tick()
W.current = "ZDF"
tick()
assert(depth.n > 0, "hooks must have fired")
assert(W.zdf.monitoring == BOTH and W.ard.monitoring == NONE, "route correct after reentrant calls")
off_and_assert_restored("reentrant off")
assert(W.ard.monitoring == BOTH and W.zdf.monitoring == BOTH)

-- 5b. A disarming lifecycle event inside the device switch stops the pass.
setup()
W.ard.monitoring = BOTH
W.hooks.set_device = function()
  W.hooks.set_device = nil
  frontend_event(EV.PROFILE)
end
request(true)
W.current = "ARD"
tick()
assert(W.device == "default" and W.ard.monitoring == BOTH, "disarm inside switch restores state")
assert(#W.logs == 0 and status().error == "", "a lifecycle stop is not an error")
check_clean("disarm inside switch")

-- 5c. Exit event while routing, then re-enable works.
setup()
request(true)
W.current = "ARD"
tick()
assert(W.ard.monitoring == BOTH)
frontend_event(EV.EXIT)
assert(W.device == "default" and W.ard.monitoring == NONE and not io.open(directory .. "/requested"))
request(true)
tick()
assert(W.device == "obs_broadcast" and W.ard.monitoring == BOTH)
frontend_event(EV.COLLECTION)
assert(W.device == "default")
check_clean("collection change")

-- 6. Rename and recreation of broadcast sources.
setup()
W.ard.monitoring = BOTH
request(true)
W.current = "ARD"
tick()
W.ard.name = "Renamed broadcast"
tick()
assert(W.ard.monitoring == NONE and W.device == "obs_broadcast", "renamed source is owned and silent")
off_and_assert_restored("rename")
assert(W.ard.monitoring == BOTH, "renamed source restored to its prior mode")

setup()
W.ard.monitoring = BOTH
request(true)
W.current = "ARD"
tick()
-- the source is deleted and recreated with the same name, user mode ONLY
local old = W.ard
local fresh = new_source("ARD Live", "ffmpeg_source", ONLY)
for i, s in ipairs(W.sources) do if s == old then W.sources[i] = fresh end end
W.program.ARD.items[1].source = fresh
tick()
assert(fresh.monitoring == BOTH and W.device == "obs_broadcast", "recreated source is adopted and routed")
assert(old.refs == 0, "reference to the removed source is dropped")
off_and_assert_restored("recreation")
assert(fresh.monitoring == ONLY, "recreated source gets its own prior mode back")

-- 6b. A broadcast source appearing monitored while sharing is on is silenced at once.
setup()
request(true)
tick()
local extra = new_source("Media", "ffmpeg_source", BOTH)
W.sources[#W.sources + 1] = extra
tick()
assert(extra.monitoring == NONE and W.device == "obs_broadcast", "late broadcast source owned")
off_and_assert_restored("late source")
assert(extra.monitoring == BOTH)

-- 7. Lua failure restores everything and is logged once.
setup()
W.ard.monitoring = BOTH
request(true)
W.current = "ARD"
tick()
local get_name = obslua.obs_source_get_name
obslua.obs_source_get_name = function() error("injected failure") end
for _ = 1, 20 do tick() end
obslua.obs_source_get_name = get_name
assert(W.device == "default" and W.ard.monitoring == BOTH, "failure restores state")
assert(#W.logs == 1 and W.logs[1]:find("injected failure"), "one log with the cause")
assert(status().error:find("injected failure") and not status().enabled)
check_clean("failure")

-- 8. The error is shown briefly, cleared on the next request.
request(true)
tick()
assert(status().error == "" and W.device == "obs_broadcast")
off_and_assert_restored("after failure")

-- 9. A failing device restore keeps owned sources silent and retries once.
setup()
W.ard.monitoring = BOTH
request(true)
W.current = "ARD"
tick()
W.device_ok = false
request(false)
for _ = 1, 10 do tick() end
assert(W.device == "obs_broadcast" and W.ard.monitoring == NONE, "restore failed: stay silent")
assert(not status().enabled and #W.logs == 1, "restore failure logged once")
W.device_ok = true
tick()
assert(W.device == "default" and W.ard.monitoring == BOTH, "retry restores")
check_clean("restore retry")

-- 10. Unload restores, including from inside a nested callback.
setup()
W.ard.monitoring = BOTH
request(true)
W.current = "ARD"
tick()
script_unload()
assert(W.device == "default" and W.ard.monitoring == BOTH and not io.open(directory .. "/requested"))
tick()
assert(W.device == "default", "no pass runs after unload")
check_clean("unload")

setup()
W.ard.monitoring = BOTH
W.hooks.set_monitoring = function()
  W.hooks.set_monitoring = nil
  script_unload()
end
request(true)
W.current = "ARD"
tick()
assert(W.device == "default" and W.ard.monitoring == BOTH, "unload inside a call restores")
check_clean("nested unload")

-- 11. Route is never audible outside the program source while switching modes.
setup()
W.ard.monitoring, W.zdf.monitoring, W.browser.monitoring = BOTH, BOTH, BOTH
request(true)
for _, scene in ipairs({ "ARD", "ZDF", "Tagesschau", "Webcam", "ZDF", "ARD" }) do
  W.current = scene
  tick()
end
off_and_assert_restored("switching")

-- 12. Scene-away and teardown under a source tail: the sources keep decoding
--     (their audio is still in flight) while the program leaves them. At no
--     call, even from reentrant callbacks, may one of them be audible on the
--     user's own output or on the broadcast sink outside the program scene,
--     and the original device returns only after every source is silent.
for _, prior in ipairs({ NONE, ONLY, BOTH }) do
  setup()
  W.ard.monitoring, W.zdf.monitoring, W.browser.monitoring = prior, prior, prior
  local nested = { n = 0 }
  W.hooks.set_monitoring = reentrant(nested)
  W.hooks.set_device = reentrant(nested)
  request(true)
  tick()
  -- Before the first pass the user's own configuration is audible by design;
  -- from the moment the route is engaged nothing may leak.
  W.watch = true
  W.current = "ARD"
  tick()
  assert(W.ard.monitoring == BOTH and W.device == "obs_broadcast")
  local device_sets = W.device_sets
  -- scene-away: the tail is still decoding, nothing may reach another device
  W.current = "Webcam"
  frontend_event(EV.SCENE_CHANGED)
  tick()
  assert(W.ard.monitoring == NONE, "scene-away silences the source")
  assert(W.device == "obs_broadcast" and W.device_sets == device_sets,
    "scene-away must not touch the monitoring device")
  -- away during a transition and back, then away to another allowed scene
  W.current = "ZDF"
  W.progress = 0.4
  frontend_event(EV.SCENE_CHANGED)
  assert(W.zdf.monitoring == NONE, "transition silent")
  W.progress = 1
  tick()
  W.current = "Tagesschau"
  tick()
  W.current = "ARD"
  tick()
  -- teardown while a source is the program (maximum tail), then again away
  request(false)
  tick()
  assert(W.device == "default", "device restored")
  assert(W.ard.monitoring == prior and W.zdf.monitoring == prior and W.browser.monitoring == prior,
    "exact prior modes restored")
  check_clean("tail teardown, prior mode " .. prior)
end

-- 12b. A failure during the tail (unrelated monitoring appears while a
--      program source plays) restores the device only after silence.
setup()
W.ard.monitoring = BOTH
request(true)
W.current = "ARD"
tick()
W.watch = true
W.mic.monitoring = BOTH
tick()
assert(W.device == "default" and W.ard.monitoring == BOTH and not sharing_requested())
check_clean("tail failure")

print("Lua routing tests passed: ownership, restore order, reentrancy, conflicts, rename/recreation, one-shot errors, unload, tail teardown")
