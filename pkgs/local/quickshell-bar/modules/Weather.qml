import QtQuick
import Quickshell.Io
import "../" as Root
import "../widgets" as Widgets

Widgets.Pill {
    id: root
    collapsed: label.text === ""

    property string weatherText: ""

    onClicked: proc.running = true

    Text {
        id: label
        color: Root.Theme.text
        font.family: Root.Theme.fontFamily
        font.weight: Root.Theme.fontWeight
        font.pixelSize: Root.Theme.fontSize
        text: root.weatherText
    }

    Process {
        id: proc
        command: ["wttrbar", "--location", "Berlin, Germany"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.weatherText = JSON.parse(text).text ?? "";
                } catch (e) {
                    root.weatherText = "";
                }
            }
        }
    }

    Timer {
        interval: 3600000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: proc.running = true
    }
}
