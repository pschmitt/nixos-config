import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root
    property var preview: ({})

    FileView {
        id: stateFile
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/hypr-snap-preview.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try { root.preview = JSON.parse(text()) }
            catch (error) { root.preview = {} }
        }
        onLoadFailed: root.preview = ({})
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            visible: root.preview.monitor === modelData.name
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            mask: Region {}
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "hypr-snap-preview"
            Rectangle {
                x: root.preview.x || 0
                y: root.preview.y || 0
                width: root.preview.width || 0
                height: root.preview.height || 0
                radius: 10
                color: "#558aa4c5"
                border.color: "#cc8aa4c5"
                border.width: 2
            }
        }
    }
}
