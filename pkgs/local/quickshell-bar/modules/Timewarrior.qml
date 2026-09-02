import QtQuick
import Quickshell.Io
import "../" as Root
import "../widgets" as Widgets

Widgets.Pill {
    id: root
    interactive: false
    collapsed: !root.active

    property bool active: false
    property string durationText: ""
    readonly property bool overtime: {
        const h = parseInt(durationText.split(":")[0], 10);
        return !isNaN(h) && h > 7;
    }

    Text {
        color: root.overtime ? Root.Theme.alert : Root.Theme.text
        font.family: Root.Theme.fontFamily
        font.weight: Root.Theme.fontWeight
        font.pixelSize: Root.Theme.fontSize
        font.bold: root.overtime
        text: root.active ? "󱤣 " + root.durationText : ""
    }

    Process {
        id: isOnProc
        command: ["timew-is-on"]
        onExited: exitCode => {
            root.active = exitCode === 0;
            if (root.active) totalProc.running = true;
        }
    }

    Process {
        id: totalProc
        command: ["timew-total", "--minutes"]
        stdout: StdioCollector {
            onStreamFinished: root.durationText = text.trim()
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: isOnProc.running = true
    }
}
