import QtQuick
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

// Screencast indicator: a pulsing red REC dot in the bar while a
// portal-based screen share is live, ported from Noctalia's
// pschmitt/screencast (noctalia-plugins.git/plugins/screencast). Detection
// is delegated to pkgs/local/screencast-state (PipeWire graph inspection
// via pw-dump), already shared with the quickshell-bar/waybar indicators
// and the go-hass-agent sensor -- no need to reimplement it here.
//
// Simplified from the Noctalia version: fixed defaults (REC label, 8px
// dot, 1200ms pulse, error color) instead of a full settings surface, and
// click-to-focus matches by class substring only (screencast-state reports
// client names, not pids, so the pid-first matching panel.luau does isn't
// available here).
PluginComponent {
    id: root

    property bool active: false
    property var apps: []

    Component.onCompleted: setVisibilityOverride(false)
    onActiveChanged: {
        if (active) clearVisibilityOverride();
        else setVisibilityOverride(false);
    }

    Process {
        id: pollProc
        command: ["@screencastState@", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                let data = { active: false, apps: [] };
                try { data = JSON.parse(text) || data; } catch (e) {}
                root.active = data.active === true;
                root.apps = data.apps || [];
            }
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: pollProc.running = true
    }

    // A reusable inline component rather than one `Rectangle { id: dot }`
    // per pill: horizontalBarPill/verticalBarPill are each instantiated as
    // their own separate object tree when the bar loads them, so an
    // animation declared as a sibling at the PluginComponent's own scope
    // could never reach an id declared inside either of them.
    component PulsingDot: Rectangle {
        property bool pulsing: false
        width: 8
        height: 8
        radius: 4
        color: Theme.error
        SequentialAnimation on opacity {
            running: pulsing
            loops: Animation.Infinite
            NumberAnimation { from: 1; to: 0.25; duration: 600; easing.type: Easing.InOutQuad }
            NumberAnimation { from: 0.25; to: 1; duration: 600; easing.type: Easing.InOutQuad }
        }
    }

    function focusApp(name) {
        focusProc.command = ["hyprctl", "dispatch", "focuswindow", "class:" + name];
        focusProc.running = true;
    }

    Process { id: focusProc }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS
            PulsingDot {
                pulsing: root.active
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                text: "REC"
                color: Theme.error
                font.weight: Font.Bold
                font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        PulsingDot { pulsing: root.active }
    }

    popoutWidth: 360
    popoutHeight: 0

    popoutContent: Component {
        PopoutComponent {
            id: popout
            headerText: "Screencast"
            detailsText: root.active ? "Screen sharing is active" : "Not sharing"
            showCloseButton: true

            Column {
                width: parent.width
                spacing: Theme.spacingXS
                visible: root.apps.length > 0

                Repeater {
                    model: root.apps

                    Row {
                        required property string modelData
                        width: parent.width
                        height: 28
                        spacing: Theme.spacingXS

                        DankIcon { name: "desktop_windows"; size: 16; color: Theme.surfaceText; anchors.verticalCenter: parent.verticalCenter }
                        StyledText {
                            width: parent.width - 16 - Theme.spacingXS
                            text: modelData
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeSmall
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.focusApp(modelData)
                        }
                    }
                }
            }

            StyledText {
                visible: root.apps.length === 0
                text: "No active screen share"
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }
}
