import QtQuick
import Quickshell.Services.UPower
import "../" as Root
import "../widgets" as Widgets

Widgets.Pill {
    id: root
    interactive: false
    readonly property UPowerDevice dev: UPower.displayDevice
    collapsed: !root.dev || !root.dev.isPresent
    readonly property bool critical: !!root.dev && root.dev.state === UPowerDeviceState.Discharging && root.dev.percentage <= 0.15

    Text {
        id: label
        color: root.critical ? Root.Theme.alert : (root.dev && root.dev.state === UPowerDeviceState.FullyCharged ? Root.Theme.ok : Root.Theme.warn)
        font.family: Root.Theme.fontFamily
        font.weight: Root.Theme.fontWeight
        font.pixelSize: Root.Theme.fontSize
        text: {
            if (!root.dev || !root.dev.isPresent) return "";
            const pct = Math.round(root.dev.percentage * 100);
            const icon = root.dev.state === UPowerDeviceState.Charging ? "󰂅" : "󰁹";
            return icon + " " + pct + "%";
        }

        SequentialAnimation on opacity {
            running: root.critical
            loops: Animation.Infinite
            NumberAnimation {
                to: 0.35
                duration: 450
                easing.type: Easing.InOutQuad
            }
            NumberAnimation {
                to: 1
                duration: 450
                easing.type: Easing.InOutQuad
            }
        }
    }
}
