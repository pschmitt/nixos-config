import QtQuick
import Quickshell.Io
import "../" as Root
import "../widgets" as Widgets

Widgets.Pill {
    id: root
    property bool enabled_: false

    readonly property string schema: "org.gnome.desktop.a11y.applications"
    readonly property string key: "screen-keyboard-enabled"

    onClicked: {
        setProc.command = ["gsettings", "set", root.schema, root.key, root.enabled_ ? "false" : "true"];
        setProc.running = true;
    }

    Text {
        color: root.enabled_ ? Root.Theme.ok : Root.Theme.muted
        font.family: Root.Theme.fontFamily
        font.weight: Root.Theme.fontWeight
        font.pixelSize: Root.Theme.fontSize
        text: ""
    }

    Process {
        id: getProc
        command: ["gsettings", "get", root.schema, root.key]
        stdout: StdioCollector {
            onStreamFinished: root.enabled_ = text.trim() === "true"
        }
    }

    Process {
        id: setProc
        onExited: getProc.running = true
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: getProc.running = true
    }
}
