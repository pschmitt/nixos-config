import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Hot edge: pushing the pointer against the left or right edge (see
// LAN_MOUSE_HOT_EDGE) of the outermost screen on that side offers to start
// lan-mouse while it is not running.
ShellRoot {
    id: root

    readonly property bool onLeft: Quickshell.env("LAN_MOUSE_HOT_EDGE") === "left"

    property bool lanMouseActive: true
    property bool offerVisible: false
    readonly property var edgeScreen: {
        let best = null
        for (const s of Quickshell.screens) {
            if (best === null
                    || (root.onLeft ? s.x < best.x : s.x + s.width > best.x + best.width))
                best = s
        }
        return best
    }

    Process {
        id: probe
        command: ["systemctl", "--user", "is-active", "--quiet", "lan-mouse.service"]
        onExited: (code, status) => {
            root.lanMouseActive = code === 0
            if (root.lanMouseActive)
                root.offerVisible = false
        }
    }

    Process {
        id: starter
        command: ["zsh", "-fc", "fpath=(/etc/profiles/per-user/$USER/share/zsh/site-functions $fpath); autoload -Uz lan-mouse::start lan-mouse::_control; lan-mouse::start"]
        onExited: (code, status) => {
            root.offerVisible = false
            probe.running = true
        }
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: probe.running = true
    }

    Timer {
        id: hideTimer
        interval: 1500
        onTriggered: root.offerVisible = false
    }

    // Invisible strip on the middle of the edge. Dropped while lan-mouse runs so it
    // never competes with lan-mouse's own layer-shell capture surfaces.
    PanelWindow {
        screen: root.edgeScreen
        visible: root.edgeScreen !== null && !root.lanMouseActive
        anchors { left: root.onLeft; right: !root.onLeft }
        implicitWidth: 2
        // Middle quarter of the edge; unanchored vertically means centered.
        implicitHeight: Math.round(root.edgeScreen.height * 0.25)
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "lan-mouse-hot-edge"

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: {
                root.offerVisible = true
                hideTimer.restart()
            }
        }
    }

    PanelWindow {
        screen: root.edgeScreen
        visible: root.edgeScreen !== null && root.offerVisible && !root.lanMouseActive
        anchors { left: root.onLeft; right: !root.onLeft }
        margins.left: 12
        margins.right: 12
        implicitWidth: 52
        implicitHeight: 52
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "lan-mouse-hot-edge-offer"

        // Noctalia palette (Indigo): surface_variant fill, primary glyph.
        Rectangle {
            anchors.fill: parent
            radius: 12
            color: area.containsMouse ? "#f0262733" : "#f01e1f27"
            border.color: area.pressed || starter.running ? "#b6c4ff" : "#33333f"
            border.width: 1
            scale: area.pressed ? 0.86 : 1
            Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
            Behavior on border.color { ColorAnimation { duration: 120 } }

            // Mouse glyph: body, button split, wheel.
            Rectangle {
                anchors.centerIn: parent
                width: 18
                height: 26
                radius: 9
                color: "transparent"
                border.color: "#b6c4ff"
                border.width: 2

                // Left button lights up on press and pulses while starting.
                Rectangle {
                    x: 2; y: 2
                    width: 7; height: 10
                    topLeftRadius: 7
                    color: "#b6c4ff"
                    opacity: area.pressed ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 90 } }
                }

                SequentialAnimation on opacity {
                    running: starter.running
                    loops: Animation.Infinite
                    onRunningChanged: if (!running) parent.opacity = 1
                    NumberAnimation { to: 0.35; duration: 350 }
                    NumberAnimation { to: 1; duration: 350 }
                }

                Rectangle {
                    x: 8; y: 4
                    width: 2; height: 6
                    radius: 1
                    color: "#b6c4ff"
                }
            }

            MouseArea {
                id: area
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: hideTimer.stop()
                onExited: hideTimer.restart()
                onClicked: starter.running = true
            }
        }
    }
}
