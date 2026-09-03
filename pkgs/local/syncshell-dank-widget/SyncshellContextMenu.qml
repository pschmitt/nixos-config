import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// Right-click quick-actions menu for the SyncShell bar pill. DMS plugins
// only get a single pillRightClickAction callback (no built-in
// context-menu primitive), so this reimplements the same
// PanelWindow + WlrLayershell overlay pattern the native bar widgets use
// for their own context menus (see DankBar/Widgets/AppsDockContextMenu.qml).
PanelWindow {
    id: root

    WindowBlur {
        targetWindow: root
        blurX: menuContainer.x
        blurY: menuContainer.y
        blurWidth: root.visible ? menuContainer.width : 0
        blurHeight: root.visible ? menuContainer.height : 0
        blurRadius: Theme.cornerRadius
    }

    WlrLayershell.namespace: "dms:syncshell-context-menu"

    property point anchorPos: Qt.point(0, 0)
    property bool isVertical: false
    property string edge: "top"
    property bool allFoldersPaused: false
    property bool busy: false

    function showAt(x, y, vertical, barEdge, foldersPaused, isBusy, targetScreen) {
        if (targetScreen) {
            root.screen = targetScreen;
        }

        anchorPos = Qt.point(x, y);
        isVertical = vertical ?? false;
        edge = barEdge ?? "top";
        allFoldersPaused = foldersPaused ?? false;
        busy = isBusy ?? false;

        visible = true;

        if (targetScreen) {
            TrayMenuManager.registerMenu(targetScreen.name, root);
        }
    }

    function close() {
        visible = false;

        if (root.screen) {
            TrayMenuManager.unregisterMenu(root.screen.name);
        }
    }

    screen: null
    visible: false
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    color: "transparent"
    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    Component.onDestruction: {
        if (root.screen) {
            TrayMenuManager.unregisterMenu(root.screen.name);
        }
    }

    Connections {
        target: PopoutManager
        function onPopoutOpening() {
            root.close();
        }
    }

    readonly property var menuActions: [
        {
            icon: "refresh",
            label: "Refresh",
            enabled: !busy,
            cmd: ["dms", "ipc", "call", "syncshell", "refresh"]
        },
        {
            icon: "document_scanner",
            label: "Rescan All",
            enabled: !busy,
            cmd: ["dms", "ipc", "call", "syncshell", "rescanAll"]
        },
        {
            icon: allFoldersPaused ? "play_arrow" : "pause",
            label: allFoldersPaused ? "Resume All" : "Pause All",
            enabled: !busy,
            cmd: ["dms", "ipc", "call", "syncshell", allFoldersPaused ? "resumeAll" : "pauseAll"]
        },
        {
            icon: "open_in_new",
            label: "Open Web UI",
            enabled: true,
            cmd: ["xdg-open", "http://127.0.0.1:8384"]
        }
    ]

    Rectangle {
        id: menuContainer

        x: {
            if (root.isVertical) {
                if (root.edge === "left") {
                    return Math.min(root.width - width - 10, root.anchorPos.x);
                } else {
                    return Math.max(10, root.anchorPos.x - width);
                }
            } else {
                const left = 10;
                const right = root.width - width - 10;
                const want = root.anchorPos.x - width / 2;
                return Math.max(left, Math.min(right, want));
            }
        }
        y: {
            if (root.isVertical) {
                const top = 10;
                const bottom = root.height - height - 10;
                const want = root.anchorPos.y - height / 2;
                return Math.max(top, Math.min(bottom, want));
            } else {
                if (root.edge === "top") {
                    return Math.min(root.height - height - 10, root.anchorPos.y);
                } else {
                    return Math.max(10, root.anchorPos.y - height);
                }
            }
        }

        width: Math.min(260, Math.max(180, menuColumn.implicitWidth + Theme.spacingS * 2))
        height: Math.max(60, menuColumn.implicitHeight + Theme.spacingS * 2)
        color: Theme.floatingSurface
        radius: Theme.cornerRadius
        border.color: BlurService.borderColor
        border.width: BlurService.borderWidth

        opacity: root.visible ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.shortDuration
                easing.type: Theme.emphasizedEasing
            }
        }

        Column {
            id: menuColumn
            width: parent.width - Theme.spacingS * 2
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: Theme.spacingS
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.spacingS
            spacing: 1

            Repeater {
                model: root.menuActions

                Rectangle {
                    required property var modelData
                    width: parent.width
                    height: 28
                    radius: Theme.cornerRadius
                    opacity: modelData.enabled ? 1 : 0.4
                    color: itemArea.containsMouse && modelData.enabled ? Theme.withAlpha(Theme.surfaceText, 0.08) : "transparent"

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingS

                        DankIcon {
                            name: modelData.icon
                            size: 14
                            color: Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: modelData.label
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceText
                            font.weight: Font.Normal
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: itemArea
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: modelData.enabled
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Quickshell.execDetached(modelData.cmd);
                            root.close();
                        }
                    }
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: root.close()
    }
}
