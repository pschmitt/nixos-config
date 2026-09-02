import QtQuick
import Quickshell

// Quickshell 0.3.0 has a bug where a PanelWindow reserving an exclusive zone
// (exclusionMode Normal/Auto) on a partially-anchored (3-edge) panel stops
// receiving pointer input entirely (confirmed empirically: hover events never
// fire, regardless of MouseArea/mask setup). Splitting the reservation out
// into its own invisible, non-interactive window works around it: this window
// only reserves the layout space so real app windows get pushed down, while
// Bar.qml (exclusionMode Ignore, no zone of its own) renders the actual
// interactive content on top of that same reserved strip.
PanelWindow {
    id: spacer

    required property ShellScreen modelData
    screen: modelData

    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: Theme.barHeight
    exclusiveZone: Theme.barHeight
    color: "transparent"
    focusable: false
}
