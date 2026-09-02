import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import "../" as Root
import "../widgets" as Widgets

Row {
    id: root
    spacing: 0

    Repeater {
        model: SystemTray.items

        delegate: Widgets.Pill {
            id: item
            required property var modelData
            pad: 3

            onClicked: {
                if (item.modelData.hasMenu) menuAnchor.open();
                else item.modelData.activate();
            }
            onRightClicked: {
                if (item.modelData.hasMenu) menuAnchor.open();
                else item.modelData.secondaryActivate();
            }

            IconImage {
                width: Root.Theme.fontSize + 2
                height: width
                source: item.modelData.icon
            }

            QsMenuAnchor {
                id: menuAnchor
                menu: item.modelData.menu
                anchor.item: item
                anchor.edges: Edges.Bottom | Edges.Left
                anchor.gravity: Edges.Bottom | Edges.Right
            }
        }
    }
}
