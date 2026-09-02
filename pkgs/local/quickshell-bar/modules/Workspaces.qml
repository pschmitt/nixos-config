import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../" as Root

Row {
    id: root
    required property ShellScreen screen
    spacing: 6

    readonly property var monitor: {
        const list = Hyprland.monitors ? Hyprland.monitors.values : [];
        for (const m of list) {
            if (m.name === root.screen.name) return m;
        }
        return null;
    }

    Repeater {
        model: Hyprland.workspaces

        delegate: Item {
            id: wsItem
            required property HyprlandWorkspace modelData
            readonly property bool isSpecial: modelData.id < 0
            readonly property bool onThisMonitor: !isSpecial && modelData.monitor === root.monitor
            readonly property bool active: modelData.focused

            width: onThisMonitor ? (active ? 26 : 12) : 0
            height: Root.Theme.barHeight - 2 * Root.Theme.barMargin
            visible: width > 0
            opacity: onThisMonitor ? 1 : 0

            Behavior on width {
                NumberAnimation {
                    duration: Root.Theme.animNormal
                    easing.type: Root.Theme.easing
                }
            }
            Behavior on opacity {
                NumberAnimation {
                    duration: Root.Theme.animNormal
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: wsItem.modelData.urgent ? Root.Theme.alert : (wsItem.active ? Root.Theme.accent : Qt.rgba(1, 1, 1, 0.14))
                Behavior on color {
                    ColorAnimation {
                        duration: Root.Theme.animFast
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: wsItem.modelData.activate()
            }
        }
    }
}
