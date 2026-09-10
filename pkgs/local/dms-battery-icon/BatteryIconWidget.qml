import QtQuick
import Quickshell.Services.UPower
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import qs.Services

// Android-inspired battery pill: percentage drawn inside the silhouette,
// with a charging bolt overlay. Ported from pschmitt/battery-icon
// (noctalia-plugins.git/plugins/battery-icon), scoped to what's both
// broadly hardware-safe and not already native to DMS: the panel adds a
// power profile selector, Bluetooth peripheral battery levels, and the
// idle-inhibitor ("caffeine") toggle on top of the pill.
//
// Deliberately not ported: charging-threshold read/write (laptop-vendor
// sysfs paths -- ThinkPad/ASUS/Framework all differ, too risky to author
// blind), the TDP/ryzenadj slider (AMD+polkit-specific, niche), fan
// rollup (fan-control plugin is out of scope), plug/unplug sounds, and
// per-click configurable actions. All battery data and thresholds come
// straight from DMS's own BatteryService/SettingsData rather than a
// separate poller, so there is nothing here to fall out of sync with it.
PluginComponent {
    id: root

    readonly property real level: BatteryService.batteryLevel
    readonly property bool charging: BatteryService.isCharging
    readonly property bool available: BatteryService.batteryAvailable

    readonly property int lowPeripheralThreshold: 20
    readonly property bool showLowPeripheralBadge: root.pluginData.show_peripheral_low_badge !== false
    readonly property bool hasLowPeripheral: root.showLowPeripheralBadge && (BatteryService.bluetoothDevices || []).some(function (d) {
        return d.percentage !== undefined && d.percentage <= root.lowPeripheralThreshold;
    })

    // Inline component, instantiated directly (no Loader/onLoaded
    // indirection): a Loader's own size only tracks its loaded item's
    // *implicit* size, and this item's real size instead comes from
    // pillWidth/pillHeight, which a Loader has no way to see -- so the
    // Loader itself rendered at 0x0 and the pill never appeared in the
    // bar. Direct instantiation binds pillWidth/pillHeight as ordinary
    // property bindings instead, which is both correctly sized and
    // reactive to bar-thickness/scale changes (the previous onLoaded
    // assignment only ever ran once, at first load).
    component BatteryPill: Item {
        property real pillWidth: 34
        property real pillHeight: 16

        width: pillWidth
        height: pillHeight
        visible: root.available

        // Silhouette: outline, small terminal nub, percentage fill.
        Rectangle {
            id: body
            anchors.fill: parent
            anchors.rightMargin: 3
            radius: 4
            color: Theme.withAlpha(Theme.surfaceText, 0.06)
            border.color: Theme.surfaceText
            border.width: 1.5
        }
        Rectangle {
            width: 3
            height: parent.height * 0.5
            anchors.left: body.right
            anchors.verticalCenter: body.verticalCenter
            radius: 1
            color: Theme.surfaceText
        }
        Rectangle {
            anchors.left: body.left
            anchors.top: body.top
            anchors.bottom: body.bottom
            anchors.margins: 2.5
            width: Math.max(0, (body.width - 5) * Math.min(1, Math.max(0, root.level / 100)))
            radius: 2
            color: root.charging ? Theme.primary : BatteryService.levelColor
        }
        StyledText {
            anchors.centerIn: body
            text: Math.round(root.level) + "%"
            font.pixelSize: Math.max(9, parent.pillHeight * 0.5)
            font.weight: Font.Bold
            color: Theme.surfaceText
            style: Text.Outline
            styleColor: Theme.withAlpha(Theme.surfaceContainer, 0.6)
        }
        DankIcon {
            visible: root.charging
            name: "bolt"
            size: Math.max(10, parent.pillHeight * 0.75)
            color: Theme.primary
            anchors.right: body.right
            anchors.top: body.top
            anchors.rightMargin: -3
            anchors.topMargin: -4
        }
        // Low-battery indicator for "other devices" (e.g. Bluetooth
        // peripherals), independent of the bolt overlay above so both can
        // show at once without colliding.
        Rectangle {
            visible: root.hasLowPeripheral
            width: 7
            height: 7
            radius: 3.5
            color: Theme.error
            border.color: Theme.surfaceContainer
            border.width: 1
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.rightMargin: -2
            anchors.topMargin: -2
        }
    }

    horizontalBarPill: Component {
        BatteryPill {
            pillWidth: 34
            pillHeight: Theme.barIconSize(root.barThickness, -6, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
        }
    }

    verticalBarPill: Component {
        BatteryPill {
            pillWidth: Theme.barIconSize(root.barThickness, -6, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
            pillHeight: 16
        }
    }

    popoutWidth: 400
    popoutHeight: 0

    popoutContent: Component {
        PopoutComponent {
            id: popout
            headerText: "Battery"
            detailsText: BatteryService.batteryStatus
            showCloseButton: true

            Row {
                width: parent.width
                spacing: Theme.spacingM

                BatteryPill {
                    pillWidth: 56
                    pillHeight: 26
                }

                Column {
                    width: parent.width - 56 - Theme.spacingM
                    spacing: 1
                    StyledText {
                        text: BatteryService.batteryHealth !== "" ? "Health: " + BatteryService.batteryHealth : "Health: unknown"
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeSmall
                    }
                    StyledText {
                        text: {
                            const t = BatteryService.formatTimeRemaining();
                            const p = BatteryService.formatPowerRate(false);
                            const parts = [];
                            if (t && t !== "Unknown") parts.push(t + (BatteryService.isCharging ? " until full" : " remaining"));
                            if (p) parts.push(p);
                            return parts.length > 0 ? parts.join(" · ") : "—";
                        }
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }
            }

            StyledText {
                visible: PowerProfileWatcher.available
                text: "Power profile"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Bold
                color: Theme.surfaceText
                topPadding: Theme.spacingM
            }

            Row {
                visible: PowerProfileWatcher.available
                width: parent.width
                spacing: Theme.spacingXS

                Repeater {
                    model: PowerProfileWatcher.availableProfiles

                    DankButton {
                        required property int modelData
                        width: (parent.width - Theme.spacingXS * (PowerProfileWatcher.availableProfiles.length - 1)) / PowerProfileWatcher.availableProfiles.length
                        height: 36
                        text: Theme.getPowerProfileLabel(modelData)
                        iconName: Theme.getPowerProfileIcon(modelData)
                        backgroundColor: PowerProfileWatcher.currentProfile === modelData ? Theme.primary : Theme.surfaceContainerHigh
                        textColor: PowerProfileWatcher.currentProfile === modelData ? Theme.onPrimary : Theme.surfaceText
                        onClicked: PowerProfileWatcher.applyProfile(modelData)
                    }
                }
            }

            StyledText {
                visible: (BatteryService.bluetoothDevices || []).length > 0
                text: "Other devices"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Bold
                color: Theme.surfaceText
                topPadding: Theme.spacingM
            }

            Column {
                width: parent.width
                spacing: Theme.spacingXS
                visible: (BatteryService.bluetoothDevices || []).length > 0

                Repeater {
                    model: BatteryService.bluetoothDevices || []

                    Row {
                        width: parent.width
                        height: 20
                        required property var modelData
                        StyledText {
                            width: parent.width - 40
                            text: modelData.name || "Device"
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                            elide: Text.ElideRight
                        }
                        StyledText {
                            width: 40
                            horizontalAlignment: Text.AlignRight
                            text: (modelData.percentage !== undefined ? Math.round(modelData.percentage) : "?") + "%"
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }
                }
            }

            Item {
                width: parent.width
                height: Theme.spacingM
            }
            DankButton {
                width: parent.width
                height: 36
                text: SessionService.idleInhibited ? "Caffeine: on (stay awake)" : "Caffeine: off"
                iconName: SessionService.idleInhibited ? "coffee" : "coffee_maker"
                backgroundColor: SessionService.idleInhibited ? Theme.primary : Theme.surfaceContainerHigh
                textColor: SessionService.idleInhibited ? Theme.onPrimary : Theme.surfaceText
                onClicked: SessionService.toggleIdleInhibit()
            }
        }
    }
}
