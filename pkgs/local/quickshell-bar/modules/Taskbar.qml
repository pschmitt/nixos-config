import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import "../" as Root
import "../widgets" as Widgets

Row {
    id: root
    required property ShellScreen screen
    spacing: Root.Theme.pillSpacing

    readonly property var monitor: {
        const list = Hyprland.monitors ? Hyprland.monitors.values : [];
        for (const m of list) {
            if (m.name === root.screen.name) return m;
        }
        return null;
    }

    Repeater {
        model: Hyprland.toplevels

        delegate: Widgets.Pill {
            id: item
            required property HyprlandToplevel modelData
            readonly property bool onThisMonitor: modelData.monitor === root.monitor
            collapsed: !onThisMonitor

            onClicked: item.modelData.wayland?.activate()

            IconImage {
                readonly property string appId: item.modelData.wayland?.appId ?? ""
                readonly property string iconName: DesktopEntries.heuristicLookup(appId)?.icon || appId

                width: Root.Theme.fontSize + 4
                height: width
                source: iconName ? Quickshell.iconPath(iconName, "image-missing") : ""
                opacity: item.modelData.activated ? 1 : 0.55
            }
        }
    }
}
