import QtQuick
import qs.Common
import qs.Widgets
import "models/PanelModel.js" as PanelModel

// Pinned desktop status card: logo/state, device/folder/pending counters,
// transfer rates, and a progress bar while syncing. Pure display; the bar
// widget's popout is where the actions (Refresh/Rescan/Pause/Resume) live.
// Mirrors SyncshellWidget.qml's status/count logic so the desktop card and
// bar pill never disagree, reading the same daemon-published state.
Item {
    id: root

    property var pluginService: null
    property string pluginId: ""
    property bool editMode: false
    property real widgetWidth: 260
    property real widgetHeight: 150
    property real minWidth: 200
    property real minHeight: 120

    property var state: pluginService && pluginService.getGlobalVar
        ? pluginService.getGlobalVar("syncshell", "state", ({})) : ({})
    property var folderRows: state && state.folderRows ? state.folderRows : []
    readonly property int activeFolders: {
        var count = 0
        for (var i = 0; i < folderRows.length; i++)
            if (folderRows[i].syncing || folderRows[i].scanning) count++
        return count
    }
    readonly property int problemFolders: {
        var count = 0
        for (var i = 0; i < folderRows.length; i++) if (folderRows[i].problem) count++
        return count
    }
    readonly property int pausedFolders: {
        var count = 0
        for (var i = 0; i < folderRows.length; i++) if (folderRows[i].paused) count++
        return count
    }
    readonly property int pendingItems: PanelModel.total(folderRows, "needItems")
    readonly property real globalBytes: PanelModel.total(folderRows, "globalBytes")
    readonly property real inSyncBytes: PanelModel.total(folderRows, "inSyncBytes")
    readonly property real syncProgress: globalBytes > 0
        ? Math.max(0, Math.min(1, inSyncBytes / globalBytes)) : 1

    // Same four-badge mapping as SyncshellWidget.qml's statusIconSource().
    function statusIconSource() {
        if (!state || state.phase === "error" || problemFolders > 0)
            return "assets/status-issue.svg";
        if (state.phase !== "ready" || activeFolders > 0)
            return "assets/status-syncing.svg";
        if (pausedFolders > 0)
            return "assets/status-paused.svg";
        return "assets/status-synced.svg";
    }

    function stateText() {
        if (!state || !state.phase || state.phase === "discovering") return "Discovering";
        if (state.phase === "loading") return "Loading";
        if (state.phase === "error") return state.lastError || "Error";
        if (problemFolders > 0) return "Needs attention";
        if (activeFolders > 0) return "Syncing";
        if (pausedFolders > 0) return "Paused";
        return "Up to date";
    }

    function stateColor() {
        if (!state || state.phase === "error" || problemFolders > 0) return Theme.error;
        if (activeFolders > 0) return Theme.primary;
        if (pausedFolders > 0) return Theme.surfaceVariantText;
        return Theme.success;
    }

    Connections {
        target: pluginService
        function onGlobalVarChanged(changedPluginId, name) {
            if (changedPluginId === "syncshell" && name === "state")
                root.state = pluginService.getGlobalVar("syncshell", "state", ({}))
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadius
        color: Theme.surfaceContainer
        opacity: 0.85
        border.color: root.editMode ? Theme.primary : "transparent"
        border.width: root.editMode ? 2 : 0

        Column {
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingS

            Row {
                width: parent.width
                spacing: Theme.spacingS

                Image {
                    source: root.statusIconSource()
                    width: 22
                    height: 22
                    sourceSize.width: width
                    sourceSize.height: height
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }
                StyledText {
                    width: parent.width - 22 - stateLabel.width - parent.spacing * 2
                    text: "Syncthing"
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                }
                StyledText {
                    id: stateLabel
                    text: root.stateText()
                    color: root.stateColor()
                    font.pixelSize: Theme.fontSizeSmall
                }
            }

            Row {
                width: parent.width
                spacing: Theme.spacingM

                Column {
                    width: (parent.width - parent.spacing * 2) / 3
                    spacing: 1
                    StyledText {
                        text: state && state.phase === "ready"
                            ? String(state.connectedDeviceCount || 0) + "/" + String(state.deviceCount || 0) : "-"
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Font.Bold
                    }
                    StyledText { text: "DEVICES"; color: Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeSmall }
                }
                Column {
                    width: (parent.width - parent.spacing * 2) / 3
                    spacing: 1
                    StyledText {
                        text: String(root.folderRows.length)
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Font.Bold
                    }
                    StyledText { text: "FOLDERS"; color: Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeSmall }
                }
                Column {
                    width: (parent.width - parent.spacing * 2) / 3
                    spacing: 1
                    StyledText {
                        text: String(root.pendingItems)
                        color: root.pendingItems > 0 ? Theme.primary : Theme.surfaceText
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Font.Bold
                    }
                    StyledText { text: "PENDING"; color: Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeSmall }
                }
            }

            Rectangle {
                visible: root.activeFolders > 0
                width: parent.width
                height: 4
                radius: 2
                color: Theme.withAlpha(Theme.primary, 0.2)
                Rectangle {
                    width: parent.width * root.syncProgress
                    height: parent.height
                    radius: parent.radius
                    color: Theme.primary
                }
            }

            StyledText {
                visible: Number(state && state.downloadBytesPerSec || 0) >= 1
                    || Number(state && state.uploadBytesPerSec || 0) >= 1
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "↓ " + PanelModel.formatRate(state && state.downloadBytesPerSec || 0)
                    + " · ↑ " + PanelModel.formatRate(state && state.uploadBytesPerSec || 0)
                color: Theme.secondary
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }
}
