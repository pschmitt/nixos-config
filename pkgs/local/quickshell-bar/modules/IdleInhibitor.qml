import QtQuick
import Quickshell.Wayland
import "../" as Root
import "../widgets" as Widgets

Widgets.Pill {
    id: root
    required property var window
    property bool active: false

    onClicked: root.active = !root.active

    IdleInhibitor {
        window: root.window
        enabled: root.active
    }

    Text {
        color: root.active ? Root.Theme.idleActive : Root.Theme.muted
        font.family: Root.Theme.fontFamily
        font.weight: Root.Theme.fontWeight
        font.pixelSize: Root.Theme.fontSize
        text: root.active ? " NO IDLE" : "󰾪 IDLE"
    }
}
