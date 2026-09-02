.pragma library

var Endpoints = {
  getConnections: "/rest/system/connections",
  getDevices: "/rest/config/devices",
  getFileInfo: "/rest/db/file",
  getFolderStatus: "/rest/db/status",
  getFolders: "/rest/config/folders",
  getEvents: "/rest/events",
  getSystemStatus: "/rest/system/status",
  scanAll: "/rest/db/scan",
  patchFolder: "/rest/config/folders/{id}"
}

function endpointPath(name, settings) {
  var path = Endpoints[name]
  if (!path) throw new Error("Unknown Syncthing endpoint: " + name)
  var values = (settings || {}).path || {}
  return path.replace(/\{([^}]+)\}/g, function(match, key) {
    if (values[key] === undefined || values[key] === null)
      throw new Error("Missing Syncthing endpoint value: " + key)
    return encodeURIComponent(String(values[key]))
  })
}

function queryString(values) {
  var parts = []
  var query = values || {}
  var keys = Object.keys(query)
  for (var i = 0; i < keys.length; i++) {
    var value = query[keys[i]]
    if (value === undefined || value === null) continue
    var list = value instanceof Array ? value : [value]
    for (var j = 0; j < list.length; j++)
      parts.push(encodeURIComponent(keys[i]) + "=" + encodeURIComponent(String(list[j])))
  }
  return parts.length ? "?" + parts.join("&") : ""
}

function parseBody(text) {
  if (!text) return null
  try { return JSON.parse(text) } catch (error) { return text }
}

function requestUrl(baseUrl, name, settings) {
  return baseUrl.replace(/\/$/, "") + endpointPath(name, settings)
    + queryString((settings || {}).query)
}

// method/body: only used by the mutation endpoints above (scanAll,
// patchFolder), which back the widget's Rescan All / Pause All / Resume
// All actions. Every read (getFolders, getFolderStatus, ...) still just
// GETs, same as upstream.
function request(baseUrl, apiKey, name, options, onSuccess, onError) {
  var settings = options || {}
  var xhr = new XMLHttpRequest()
  var completed = false
  function fail(message) {
    if (completed) return
    completed = true
    onError({ status: xhr.status || 0, message: message })
  }
  var method = settings.method || "GET"
  xhr.open(method, requestUrl(baseUrl, name, settings), true)
  xhr.setRequestHeader("Accept", "application/json")
  if (apiKey) xhr.setRequestHeader("X-API-Key", apiKey)
  var body = settings.body !== undefined ? JSON.stringify(settings.body) : undefined
  if (body !== undefined) xhr.setRequestHeader("Content-Type", "application/json")
  xhr.onreadystatechange = function() {
    if (xhr.readyState !== 4 || completed) return
    if (xhr.status >= 200 && xhr.status < 300) {
      completed = true
      onSuccess(parseBody(xhr.responseText))
    } else fail("HTTP " + (xhr.status || 0))
  }
  xhr.onerror = function() { fail("Connection failed") }
  xhr.send(body)
  return xhr
}
