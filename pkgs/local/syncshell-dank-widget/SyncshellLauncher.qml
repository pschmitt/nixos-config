import QtQuick
import Quickshell
import qs.Services

// Syncthing launcher provider — type /st in the launcher.
//
// Lists monitored folders (filtered by the query text against their label);
// selecting one triggers a rescan of just that folder via the daemon's
// rescanFolder IPC call (SyncshellDaemon.qml), same as clicking a folder
// row's Rescan action in the bar popout, but reachable without opening it.
Item {
    id: root

    property var pluginService: null
    property string trigger: "/st"

    signal itemsChanged()

    property var state: pluginService && pluginService.getGlobalVar
        ? pluginService.getGlobalVar("syncshell", "state", ({})) : ({})
    property var folderRows: state && state.folderRows ? state.folderRows : []

    Connections {
        target: pluginService
        function onGlobalVarChanged(changedPluginId, name) {
            if (changedPluginId === "syncshell" && name === "state") {
                root.state = pluginService.getGlobalVar("syncshell", "state", ({}))
                root.itemsChanged()
            }
        }
    }

    function iconFor(folder) {
        if (folder.problem) return "material:error"
        if (folder.paused) return "material:pause_circle"
        if (folder.scanning) return "material:search"
        if (folder.syncing) return "material:sync"
        return "material:check_circle"
    }

    function statusText(folder) {
        if (folder.problem) return folder.error || "Needs attention"
        if (folder.paused) return "Paused"
        if (folder.scanning) return "Scanning"
        if (folder.syncing) return "Syncing"
        return "Up to date"
    }

    function getItems(query) {
        var rows = root.folderRows
        var q = String(query || "").trim().toLowerCase()
        var results = []
        for (var i = 0; i < rows.length; i++) {
            var folder = rows[i]
            if (q.length > 0 && String(folder.label || "").toLowerCase().indexOf(q) === -1)
                continue
            results.push({
                name: folder.label,
                icon: iconFor(folder),
                comment: statusText(folder) + " · Rescan this folder",
                action: "rescan:" + folder.position,
                categories: ["Syncthing"]
            })
        }
        return results
    }

    function executeItem(item) {
        if (!item || !item.action) return
        var parts = item.action.split(":")
        var type = parts[0]
        var data = parts.slice(1).join(":")
        if (type === "rescan") {
            Quickshell.execDetached(["dms", "ipc", "call", "syncshell", "rescanFolder", data])
            if (typeof ToastService !== "undefined")
                ToastService.showInfo("Syncthing", "Rescan started: " + item.name)
        }
    }
}
