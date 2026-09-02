import QtQuick
import Quickshell
import "modules"

PanelWindow {
    id: bar

    required property ShellScreen modelData
    screen: modelData

    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: Theme.barHeight
    // Space is reserved by the companion BarSpacer window, not here — see its
    // comment for why. Ignore is required so this window doesn't try (and
    // fail) to also carry an exclusive zone.
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    Rectangle {
        id: surface
        anchors.fill: parent
        anchors.margins: Theme.barMargin
        radius: Theme.barRadius
        color: Theme.bg
        border.color: Qt.rgba(1, 1, 1, 0.06)
        border.width: 1

        // Entrance animation: slide + fade in on startup.
        opacity: 0
        Component.onCompleted: entranceAnim.start()
        NumberAnimation {
            id: entranceAnim
            target: surface
            property: "opacity"
            from: 0
            to: 1
            duration: Theme.animSlow
            easing.type: Theme.easing
        }

        Row {
            id: leftRow
            anchors.left: parent.left
            anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.pillSpacing

            Workspaces {
                screen: bar.screen
            }
            Submap {}
            Taskbar {
                screen: bar.screen
            }
        }

        Row {
            id: centerRow
            anchors.centerIn: parent
            spacing: Theme.pillSpacing

            Weather {}
            Clock {}
            Timewarrior {}
        }

        Row {
            id: rightRow
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.pillSpacing

            Screencast {}
            Tray {}
            IdleInhibitor {
                window: bar
            }
            SoftKeyboard {
                visible: Config.enableSoftKeyboard
            }
            AudioSource {}
            Media {}
            AudioSink {}
            Load {}
            PowerProfile {}
            Battery {}
        }
    }
}
