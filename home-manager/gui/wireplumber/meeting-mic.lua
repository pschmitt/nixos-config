-- Feed the "Meeting Microphone" virtual source.
--
-- WirePlumber never links anything into a source, so this keeps links from
-- the denoised microphone and from soundboard clips (streams tagged with
-- meeting-mic.feed = true) to the virtual source's input ports. It reconciles
-- on every port or link change, so the graph also comes up when the
-- microphone appears after WirePlumber (boot, replug) and heals removed links.

local log = Log.open_topic ("s-meeting-mic")

local MIC_NODE = "meeting_source"
local FEED_NODES = { rnnoise_source = true }

local nodes_om = ObjectManager { Interest { type = "node" } }
local ports_om = ObjectManager { Interest { type = "port" } }
local links_om = ObjectManager { Interest { type = "link" } }

-- Link proxies owned by this script; dropping one destroys its link.
local owned = {}

local function isFeed (node)
  local props = node.properties
  return FEED_NODES [props ["node.name"]] or props ["meeting-mic.feed"] == "true"
end

local function nodePorts (node, direction)
  local ports = {}
  for port in ports_om:iterate {
    Constraint { "node.id", "=", tostring (node ["bound-id"]) },
    Constraint { "port.direction", "=", direction },
  } do
    if direction == "in" or port.properties ["port.monitor"] ~= "true" then
      table.insert (ports, port)
    end
  end
  return ports
end

local function channelsMatch (out_port, in_port)
  local out_ch = out_port.properties ["audio.channel"]
  local in_ch = in_port.properties ["audio.channel"]
  return out_ch == in_ch or out_ch == "MONO" or in_ch == "MONO"
end

local function isLinked (out_port, in_port)
  return links_om:lookup {
    Constraint { "link.output.port", "=", tostring (out_port ["bound-id"]) },
    Constraint { "link.input.port", "=", tostring (in_port ["bound-id"]) },
  } ~= nil
end

local MAX_RETRIES = 20
local retries = 0
local retry_pending = false
local reconcile

local function scheduleRetry ()
  if retry_pending or retries >= MAX_RETRIES then
    return
  end
  retries = retries + 1
  retry_pending = true
  Core.timeout_add (250, function ()
    retry_pending = false
    reconcile ()
    return false
  end)
end

local function link (feed, out_port, mic, in_port)
  local key = out_port ["bound-id"] .. ":" .. in_port ["bound-id"]
  if owned [key] or isLinked (out_port, in_port) then
    return
  end

  log:info (string.format ("linking %s:%s -> %s:%s",
      feed.properties ["node.name"], out_port.properties ["port.name"],
      mic.properties ["node.name"], in_port.properties ["port.name"]))

  local entry = {
    link = Link ("link-factory", {
      ["link.output.node"] = feed ["bound-id"],
      ["link.output.port"] = out_port ["bound-id"],
      ["link.input.node"] = mic ["bound-id"],
      ["link.input.port"] = in_port ["bound-id"],
    }),
  }
  owned [key] = entry
  entry.link:activate (Feature.Proxy.BOUND, function (l, e)
    if e then
      -- A new stream's ports can show up before it accepts links; retry.
      log:info ("failed to link " .. key .. ", retrying: " .. tostring (e))
      owned [key] = nil
      scheduleRetry ()
    else
      retries = 0
      entry.id = l ["bound-id"]
    end
  end)
end

function reconcile ()
  local mic = nodes_om:lookup { Constraint { "node.name", "=", MIC_NODE } }
  if not mic then
    return
  end
  local in_ports = nodePorts (mic, "in")

  for node in nodes_om:iterate () do
    if isFeed (node) then
      for _, out_port in ipairs (nodePorts (node, "out")) do
        for _, in_port in ipairs (in_ports) do
          if channelsMatch (out_port, in_port) then
            link (node, out_port, mic, in_port)
          end
        end
      end
    end
  end
end

-- Forget links that went away (port removed, or unlinked by hand) so the next
-- reconcile can recreate them.
local function forget ()
  for key, entry in pairs (owned) do
    if entry.id and not links_om:lookup {
      Constraint { "object.id", "=", tostring (entry.id) },
    } then
      owned [key] = nil
    end
  end
end

ports_om:connect ("object-added", reconcile)
ports_om:connect ("object-removed", function ()
  forget ()
  reconcile ()
end)
links_om:connect ("object-removed", function ()
  forget ()
  reconcile ()
end)

nodes_om:activate ()
links_om:activate ()
ports_om:activate ()
