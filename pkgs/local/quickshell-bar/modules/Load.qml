import QtQuick
import Quickshell.Io
import "../" as Root
import "../widgets" as Widgets

Widgets.Pill {
    id: root
    interactive: false

    FileView {
        id: fv
        path: "/proc/loadavg"
    }

    Text {
        color: Root.Theme.text
        font.family: Root.Theme.fontFamily
        font.weight: Root.Theme.fontWeight
        font.pixelSize: Root.Theme.fontSize
        text: fv.text().split(" ")[0] || "0.00"
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: fv.reload()
    }
}
