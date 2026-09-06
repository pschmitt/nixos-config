import QtQuick
import Quickshell
import Quickshell.Io
import "../" as Root
import "../widgets" as Widgets

Widgets.Pill {
    id: root
    interactive: false
    collapsed: !root.active

    property bool active: false
    property string apps: ""

    Text {
        color: Root.Theme.alert
        font.family: Root.Theme.fontFamily
        font.weight: Root.Theme.fontWeight
        font.pixelSize: Root.Theme.fontSize
        font.bold: true
        text: root.active ? " SCREENCASTING" : ""
    }

    // screencast-state reads the PipeWire graph directly, so this no longer
    // depends on the xdg-portal-screencast-watcher service and its
    // /tmp/screencast.json state file.
    Process {
        id: stateProc
        command: ["screencast-state", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const obj = JSON.parse(text);
                    root.active = obj.active === true;
                    root.apps = (obj.apps || []).join(", ");
                } catch (e) {
                    root.active = false;
                    root.apps = "";
                }
            }
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: stateProc.running = true
    }
}
