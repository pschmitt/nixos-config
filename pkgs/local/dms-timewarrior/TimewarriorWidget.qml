import QtQuick
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property bool active: false
    property string durationText: ""
    readonly property bool overtime: {
        const h = parseInt(durationText.split(":")[0], 10);
        return !isNaN(h) && h > 7;
    }

    Component.onCompleted: setVisibilityOverride(false)

    onActiveChanged: {
        if (active) clearVisibilityOverride();
        else setVisibilityOverride(false);
    }

    Process {
        id: isOnProc
        command: ["@timewIsOn@"]
        onExited: exitCode => {
            root.active = exitCode === 0;
            if (root.active) totalProc.running = true;
        }
    }

    Process {
        id: totalProc
        command: ["@timewTotal@", "--minutes"]
        stdout: StdioCollector {
            onStreamFinished: root.durationText = text.trim()
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: isOnProc.running = true
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS
            DankIcon {
                name: "timer"
                color: root.overtime ? Theme.error : Theme.surfaceText
                size: Theme.iconSize - 5
            }
            StyledText {
                text: root.durationText
                color: root.overtime ? Theme.error : Theme.surfaceText
                font.pixelSize: Theme.fontSizeMedium
                font.weight: root.overtime ? Font.Bold : Font.Normal
            }
        }
    }

    verticalBarPill: Component {
        DankIcon {
            name: "timer"
            color: root.overtime ? Theme.error : Theme.surfaceText
            size: Theme.iconSize - 4
        }
    }
}
