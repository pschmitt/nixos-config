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

    property string weekTotalText: "--"
    property string monthTotalText: "--"
    property string yearTotalText: "--"
    property var weekDays: []

    function refreshSummary() {
        weekTotalProc.running = true;
        monthTotalProc.running = true;
        yearTotalProc.running = true;
        weekBreakdownProc.running = true;
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

    Process {
        id: weekTotalProc
        command: ["@timewTotal@", "--minutes", ":week"]
        stdout: StdioCollector {
            onStreamFinished: root.weekTotalText = text.trim() || "0:00"
        }
    }

    Process {
        id: monthTotalProc
        command: ["@timewTotal@", "--minutes", ":month"]
        stdout: StdioCollector {
            onStreamFinished: root.monthTotalText = text.trim() || "0:00"
        }
    }

    Process {
        id: yearTotalProc
        command: ["@timewTotal@", "--minutes", ":year"]
        stdout: StdioCollector {
            onStreamFinished: root.yearTotalText = text.trim() || "0:00"
        }
    }

    Process {
        id: weekBreakdownProc
        command: ["@timewWeekBreakdown@"]
        stdout: StdioCollector {
            onStreamFinished: {
                const trimmed = text.trim();
                root.weekDays = trimmed.length === 0 ? [] : trimmed.split("\n").map(line => {
                    const [date, dow, duration] = line.split("\t");
                    return { date, dow, duration };
                });
            }
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
                size: Theme.barIconSize(root.barThickness, -6, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                text: root.durationText
                color: root.overtime ? Theme.error : Theme.surfaceText
                font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                font.weight: root.overtime ? Font.Bold : Theme.fontWeight
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        DankIcon {
            name: "timer"
            color: root.overtime ? Theme.error : Theme.surfaceText
            size: Theme.barIconSize(root.barThickness, -6, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
        }
    }

    popoutWidth: 320

    popoutContent: Component {
        PopoutComponent {
            id: popoutColumn

            headerText: "Timewarrior"
            showCloseButton: true

            Component.onCompleted: root.refreshSummary()

            Connections {
                target: parentPopout
                function onOpened() {
                    root.refreshSummary();
                }
            }

            Row {
                width: parent.width
                spacing: Theme.spacingS

                Repeater {
                    model: [
                        { label: "Week", value: root.weekTotalText },
                        { label: "Month", value: root.monthTotalText },
                        { label: "Year", value: root.yearTotalText }
                    ]

                    StyledRect {
                        width: (parent.width - Theme.spacingS * 2) / 3
                        height: 56
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHigh

                        Column {
                            anchors.centerIn: parent
                            spacing: 2

                            StyledText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.value
                                font.pixelSize: Theme.fontSizeLarge
                                font.weight: Font.Bold
                                color: Theme.surfaceText
                            }

                            StyledText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.label
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                        }
                    }
                }
            }

            StyledText {
                text: "This week"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Bold
                color: Theme.surfaceText
                topPadding: Theme.spacingS
            }

            Column {
                width: parent.width
                spacing: Theme.spacingXS
                visible: root.weekDays.length > 0

                Repeater {
                    model: root.weekDays

                    Item {
                        width: parent.width
                        height: dayLabel.implicitHeight

                        StyledText {
                            id: dayLabel
                            anchors.left: parent.left
                            text: modelData.dow + " " + modelData.date
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        StyledText {
                            anchors.right: parent.right
                            text: modelData.duration
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }
                }
            }

            StyledText {
                visible: root.weekDays.length === 0
                text: "No tracked time this week"
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
                bottomPadding: Theme.spacingS
            }
        }
    }
}
