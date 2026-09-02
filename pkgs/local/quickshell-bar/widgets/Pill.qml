import QtQuick
import "../" as Root

// Plain Rectangle, not Quickshell.Widgets' WrapperRectangle: WrapperRectangle
// was found to silently swallow both hover and click events for a MouseArea
// declared alongside it (confirmed empirically — a plain MouseArea directly
// on the window worked, the exact same MouseArea nested in a WrapperRectangle
// never received a single event). Not worth the convenience.
Rectangle {
    id: pill

    default property alias data: row.data
    property bool collapsed: false
    property bool interactive: true
    property real pad: Root.Theme.pillPad

    signal clicked
    signal rightClicked
    signal wheelUp
    signal wheelDown

    radius: Root.Theme.pillRadius
    color: mouse.containsMouse && interactive ? Qt.lighter(Root.Theme.bg, 1.7) : "transparent"

    implicitWidth: row.implicitWidth + 2 * pill.pad
    implicitHeight: Root.Theme.barHeight - 2 * Root.Theme.barMargin

    visible: width > 0

    scale: collapsed ? 0.6 : (mouse.pressed && interactive ? 0.92 : 1)
    opacity: collapsed ? 0 : 1
    Behavior on scale {
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
    Behavior on implicitWidth {
        NumberAnimation {
            duration: Root.Theme.animNormal
            easing.type: Root.Theme.easing
        }
    }
    Behavior on color {
        ColorAnimation {
            duration: Root.Theme.animFast
        }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 4
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: pill.interactive
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) pill.rightClicked();
            else pill.clicked();
        }
        onWheel: wheel => {
            if (wheel.angleDelta.y > 0) pill.wheelUp();
            else if (wheel.angleDelta.y < 0) pill.wheelDown();
        }
    }
}
