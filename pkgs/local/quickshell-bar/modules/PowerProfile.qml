import QtQuick
import Quickshell.Services.UPower
import "../" as Root
import "../widgets" as Widgets

Widgets.Pill {
    id: root

    onClicked: {
        const order = [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance];
        const idx = order.indexOf(PowerProfiles.profile);
        PowerProfiles.profile = order[(idx + 1) % order.length];
    }

    Text {
        color: PowerProfiles.profile === PowerProfile.Performance ? Root.Theme.alert : PowerProfiles.profile === PowerProfile.PowerSaver ? Root.Theme.ok : Root.Theme.text
        font.family: Root.Theme.fontFamily
        font.weight: Root.Theme.fontWeight
        font.pixelSize: Root.Theme.fontSize
        text: PowerProfiles.profile === PowerProfile.Performance ? "" : PowerProfiles.profile === PowerProfile.PowerSaver ? "" : ""
    }
}
