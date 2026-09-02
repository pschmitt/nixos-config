import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Modules.Plugins
import "core"
import "models/PanelModel.js" as PanelModel

PluginComponent {
    id: root

    property string phase: "discovering"
    property string lastError: ""
    property string apiKey: ""
    property string executable: String(pluginData.syncthingExecutable || "syncthing")
    property string baseUrl: String(pluginData.webUiUrl || "http://127.0.0.1:8384")
    property int refreshIntervalSec: Math.max(15, Number(pluginData.refreshIntervalSec || 60))
    property int generation: 0
    property var requests: []
    property var folders: []
    property var folderStatuses: ({})
    property var devices: []
    property var connections: ({})
    property real downloadBytesPerSec: 0
    property real uploadBytesPerSec: 0
    property var previousConnectionTotal: ({})
    property int eventSince: 0
    property bool eventsInitialized: false
    property bool eventPolling: false
    property var folderActivity: ({})
    property string localDeviceId: ""
    property string keyOutput: ""
    property bool busy: false

    readonly property bool online: phase === "ready"
    readonly property int connectedDeviceCount: {
        var count = localDeviceId ? 1 : 0
        var values = connections && connections.connections ? connections.connections : ({})
        var ids = Object.keys(values)
        for (var i = 0; i < ids.length; i++) if (values[ids[i]].connected === true) count++
        return count
    }
    readonly property bool allFoldersPaused: folders.length > 0
        && folders.every(function(folder) { return folder.paused === true })

    ApiClient {
        id: api
        baseUrl: root.baseUrl
        apiKey: root.apiKey
    }

    function publicState() {
        return {
            phase: phase,
            lastError: lastError,
            busy: busy,
            allFoldersPaused: allFoldersPaused,
            folderRows: PanelModel.publicFolderRows({
                folders: folders,
                folderStatuses: folderStatuses,
                localDeviceId: localDeviceId,
                folderActivity: folderActivity
            }, Quickshell.env("HOME")),
            deviceCount: devices.length,
            connectedDeviceCount: connectedDeviceCount,
            downloadBytesPerSec: downloadBytesPerSec,
            uploadBytesPerSec: uploadBytesPerSec
        }
    }

    function publish() {
        if (pluginService && pluginService.setGlobalVar)
            pluginService.setGlobalVar(pluginId, "state", publicState())
    }

    function track(request) {
        requests.push(request)
        return request
    }

    function request(name, options, success, failure) {
        var current = generation
        return track(api.request(name, options, function(data) {
            if (current !== root.generation) return
            success(data)
        }, function(error) {
            if (current !== root.generation) return
            if (failure) failure(error)
        }))
    }

    function discover() {
        if (keyProcess.running) return
        generation++
        phase = "discovering"
        lastError = ""
        keyOutput = ""
        publish()
        keyProcess.command = [executable, "cli", "config", "gui", "dump-json"]
        keyProcess.running = true
    }

    function refresh() {
        if (!apiKey) { discover(); return }
        generation++
        phase = "loading"
        lastError = ""
        folderStatuses = ({})
        publish()
        var pending = 4
        function finished() {
            pending--
            if (pending === 0) { root.phase = "ready"; root.publish() }
        }
        function failed(error) {
            root.phase = "error"
            root.lastError = error && error.message ? String(error.message) : "Connection failed"
            root.publish()
        }
        request("getSystemStatus", {}, function(data) {
            root.localDeviceId = String((data || {}).myID || ""); finished()
        }, failed)
        request("getConnections", {}, function(data) {
            root.updateConnections(data || ({})); finished()
        }, failed)
        request("getDevices", {}, function(data) {
            root.devices = data instanceof Array ? data : []; finished()
        }, failed)
        request("getFolders", {}, function(data) {
            root.folders = data instanceof Array ? data : []
            for (var i = 0; i < root.folders.length; i++) root.fetchFolder(root.folders[i].id)
            finished()
        }, failed)
    }

    // Rescan All: POST /rest/db/scan with no folder param scans every folder.
    function rescanAll() {
        if (!apiKey || busy) return
        busy = true
        publish()
        request("scanAll", { method: "POST" }, function() {
            root.busy = false
            root.refresh()
        }, function(error) {
            root.busy = false
            root.lastError = error && error.message ? String(error.message) : "Rescan failed"
            root.publish()
        })
    }

    // Pause All / Resume All: Syncthing has no single "pause everything"
    // endpoint, so PATCH each folder's `paused` flag individually (the same
    // effect as the folder-level pause toggle in Syncthing's own web UI).
    function setAllPaused(paused) {
        if (!apiKey || busy || folders.length === 0) return
        busy = true
        publish()
        var pending = folders.length
        var failed = false
        function done(error) {
            if (error) failed = true
            pending--
            if (pending > 0) return
            root.busy = false
            if (failed) root.lastError = "Pause update failed"
            root.refresh()
        }
        for (var i = 0; i < folders.length; i++) {
            request("patchFolder", {
                method: "PATCH",
                path: { id: folders[i].id },
                body: { paused: paused }
            }, function() { done(false) }, function() { done(true) })
        }
    }

    function pauseAll() { setAllPaused(true) }
    function resumeAll() { setAllPaused(false) }

    function updateConnections(data) {
        connections = data
        var total = data && data.total ? data.total : ({})
        var rate = PanelModel.sampleRate(previousConnectionTotal, total)
        downloadBytesPerSec = rate.downloadBytesPerSec
        uploadBytesPerSec = rate.uploadBytesPerSec
        previousConnectionTotal = total
    }

    function sampleConnections() {
        if (!apiKey || phase === "error") return
        api.request("getConnections", {}, function(data) {
            root.updateConnections(data || ({}))
            root.publish()
        }, function() {})
    }

    function pollEvents() {
        if (!apiKey || eventPolling || phase === "error") return
        eventPolling = true
        api.request("getEvents", { query: { since: eventSince, limit: 100, timeout: 0 } }, function(data) {
            root.eventPolling = false
            var events = data instanceof Array ? data : []
            if (!root.eventsInitialized) {
                root.eventsInitialized = true
                if (events.length) root.eventSince = Number(events[events.length - 1].id || 0)
                return
            }
            var nextActivity = Object.assign({}, root.folderActivity)
            var nextStatuses = Object.assign({}, root.folderStatuses)
            for (var i = 0; i < events.length; i++) {
                var event = events[i] || ({})
                var payload = event.data || ({})
                root.eventSince = Math.max(root.eventSince, Number(event.id || 0))
                if (event.type === "FolderSummary" && payload.folder && payload.summary)
                    nextStatuses[String(payload.folder)] = payload.summary
                if (event.type === "ItemStarted" && payload.folder && payload.item)
                    nextActivity[String(payload.folder)] = String(payload.item)
                if (event.type === "ItemFinished" && payload.folder && payload.item
                        && nextActivity[String(payload.folder)] === String(payload.item))
                    delete nextActivity[String(payload.folder)]
            }
            root.folderStatuses = nextStatuses
            root.folderActivity = nextActivity
            root.publish()
        }, function() { root.eventPolling = false })
    }

    function fetchFolder(folderId) {
        request("getFolderStatus", { query: { folder: folderId } }, function(data) {
            var next = Object.assign({}, root.folderStatuses)
            next[String(folderId)] = data || ({})
            root.folderStatuses = next
            root.publish()
        }, function() {})
    }

    Process {
        id: keyProcess
        command: []
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.keyOutput = text
        }
        onExited: function(exitCode) {
            var config = null
            try { config = JSON.parse(root.keyOutput) } catch (error) {}
            var key = config ? String(config.apiKey || "").trim() : ""
            root.keyOutput = ""
            if (exitCode === 0 && key) {
                root.apiKey = key
                root.baseUrl = (config.useTLS === true ? "https" : "http") + "://127.0.0.1:8384"
                root.refresh()
            } else {
                root.phase = "error"
                root.lastError = "Could not discover the local Syncthing API"
                root.publish()
            }
        }
    }

    Timer {
        interval: root.refreshIntervalSec * 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Timer {
        interval: 2000
        repeat: true
        running: true
        onTriggered: {
            root.sampleConnections()
            root.pollEvents()
        }
    }

    IpcHandler {
        target: "syncshell"
        function refresh(): void { root.refresh() }
        function rescanAll(): void { root.rescanAll() }
        function pauseAll(): void { root.pauseAll() }
        function resumeAll(): void { root.resumeAll() }
        function openFolder(index: string): string {
            var position = Number(index)
            if (position !== Math.floor(position) || position < 0 || position >= root.folders.length)
                return "Invalid folder"
            var folder = root.folders[position] || ({})
            var path = PanelModel.resolveFolderPath(folder.path, Quickshell.env("HOME"))
            if (!path) return "Folder path unavailable"
            Quickshell.execDetached(["xdg-open", path])
            return "Opened folder"
        }
        function status(): string {
            return "phase=" + root.phase + " folders=" + root.folders.length
                + " devices=" + root.connectedDeviceCount + "/" + root.devices.length
                + (root.lastError ? " error=" + root.lastError : "")
        }
    }

    Component.onDestruction: {
        generation++
        eventPolling = false
        apiKey = ""
        keyOutput = ""
    }
}
