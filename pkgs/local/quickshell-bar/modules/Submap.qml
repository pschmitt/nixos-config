import QtQuick
import Quickshell.Hyprland
import "../" as Root
import "../widgets" as Widgets

Widgets.Pill {
    id: root
    interactive: false
    collapsed: label.text === ""

    property string currentSubmap: ""

    Text {
        id: label
        color: Root.Theme.accent
        font.family: Root.Theme.fontFamily
        font.weight: Root.Theme.fontWeight
        font.pixelSize: Root.Theme.fontSize
        font.bold: true
        text: root.currentSubmap
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "submap") root.currentSubmap = event.data;
        }
    }
}
