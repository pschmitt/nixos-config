import QtQuick
import "../" as Root
import "../widgets" as Widgets

Widgets.Pill {
    id: root
    interactive: false

    Text {
        color: Root.Theme.text
        font.family: Root.Theme.fontFamily
        font.weight: Root.Theme.fontWeight
        font.pixelSize: Root.Theme.fontSize
        font.bold: true
        text: Qt.formatDateTime(now.date, "hh:mm:ss")
    }

    QtObject {
        id: now
        property date date: new Date()
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: now.date = new Date()
    }
}
