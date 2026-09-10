import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import qs.Services

// Timewarrior widget: bar pill (current interval duration) plus a popout
// with week/month/year totals, a last-BREAKDOWN_DAYS-days breakdown, and an
// editable list of the selected day's intervals (start/end time edit,
// delete). Ported from pschmitt/timewarrior's bar.luau/panel.luau/
// service.luau (noctalia-plugins.git/plugins/timewarrior) -- the
// start/stop toggle, per-day drill-down and inline interval editing are new
// here; the totals/week-breakdown pieces already existed in this widget.
PluginComponent {
    id: root

    readonly property int overtimeHours: Math.max(1, Number(pluginData.overtime_hours || 7))
    readonly property int pollIntervalSec: Math.max(2, Number(pluginData.poll_interval || 5))

    property bool active: false
    property string durationText: ""
    readonly property bool overtime: {
        const h = parseInt(durationText.split(":")[0], 10);
        return !isNaN(h) && h > root.overtimeHours;
    }

    property string weekTotalText: "--"
    property string monthTotalText: "--"
    property string yearTotalText: "--"
    property var weekDays: []

    // Last BREAKDOWN_DAYS days of raw `timew export` intervals, grouped by
    // local calendar date: { "YYYY-MM-DD": [ { id, startEpoch, endEpoch,
    // open, duration }, ... ] }. One export covers both the day totals above
    // (weekDays keeps its own :week export -- unchanged) and this drill-down.
    readonly property int breakdownDays: Math.min(62, Math.max(2, Number(pluginData.breakdown_days || 14)))
    property var intervalsByDate: ({})
    property string selectedDate: ""
    property string todayDate: Qt.formatDate(new Date(), "yyyy-MM-dd")
    property bool busy: false
    property string errorText: ""

    // { id, field } of the cell currently showing an edit field, or null.
    property var editingCell: null
    // id of the interval whose delete button is armed (two-click confirm).
    property var pendingDeleteId: null

    // timew-is-on/timew-total/timew-week-breakdown each export
    // TIMEWARRIORDB internally, but the raw `timew` calls below (added on
    // top of those pre-existing helpers) talk to the binary directly, so
    // they need the same resolution done for them -- otherwise `timew`
    // falls back to its own default database, not the one those helpers
    // (and this widget's own totals) actually use.
    function timewarriorDb() {
        const configured = Quickshell.env("TIMEWARRIORDB");
        if (configured) return configured;
        return (Quickshell.env("HOME") || "") + "/.config/timewarrior";
    }

    function refreshSummary() {
        // Recomputed here rather than as a one-shot property initializer:
        // this widget stays loaded across midnight, and `new Date()` inside
        // a QML property binding isn't reactive -- it would only ever
        // evaluate once, at creation.
        root.todayDate = Qt.formatDate(new Date(), "yyyy-MM-dd");
        weekTotalProc.running = true;
        monthTotalProc.running = true;
        yearTotalProc.running = true;
        weekBreakdownProc.running = true;
        // Set imperatively rather than as a `command:` binding: the start
        // date is derived from `new Date()`, which QML's binding engine
        // does not treat as reactive, so a binding would freeze at
        // whichever day the widget first loaded instead of sliding forward.
        intervalsProc.command = ["env", "TIMEWARRIORDB=" + root.timewarriorDb(), "@timew@", "export", root.breakdownStartDate(), "-", "tomorrow"];
        intervalsProc.running = true;
    }

    Component.onCompleted: setVisibilityOverride(false)

    onActiveChanged: {
        if (active) clearVisibilityOverride();
        else setVisibilityOverride(false);
    }

    function activeDate() {
        return root.selectedDate || root.todayDate;
    }

    function rowsForActiveDate() {
        return root.intervalsByDate[root.activeDate()] || [];
    }

    function clockText(epoch) {
        if (!epoch) return "";
        const d = new Date(epoch * 1000);
        return Qt.formatTime(d, "hh:mm");
    }

    function weekdayFor(date) {
        for (let i = 0; i < root.weekDays.length; i++)
            if (root.weekDays[i].date === date) return root.weekDays[i].dow;
        const rows = root.intervalsByDate[date];
        if (rows && rows.length > 0) return Qt.formatDate(new Date(rows[0].startEpoch * 1000), "ddd");
        return "";
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

    // One `timew export <start> - tomorrow` JSON pull, grouped client-side
    // into per-day interval rows -- same window as service.luau's
    // refreshSummary()/intervalsByDate() combined into a single request.
    function breakdownStartDate() {
        const d = new Date();
        d.setDate(d.getDate() - (root.breakdownDays - 1));
        return Qt.formatDate(d, "yyyy-MM-dd");
    }

    function formatDuration(seconds) {
        const total = Math.max(0, Math.floor(seconds || 0));
        const h = Math.floor(total / 3600);
        const m = Math.floor((total % 3600) / 60);
        return h + ":" + String(m).padStart(2, "0");
    }

    // Timewarrior JSON timestamps are UTC "YYYYMMDDTHHMMSSZ".
    function parseTimewEpoch(value) {
        if (!value) return null;
        const m = /^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z$/.exec(value);
        if (!m) return null;
        return Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]), Number(m[4]), Number(m[5]), Number(m[6])) / 1000;
    }

    Process {
        id: intervalsProc
        stdout: StdioCollector {
            onStreamFinished: {
                let entries = [];
                try { entries = JSON.parse(text) || []; } catch (e) { entries = []; }
                const now = Math.floor(Date.now() / 1000);
                const byDate = {};
                for (const entry of entries) {
                    const start = root.parseTimewEpoch(entry.start);
                    if (start === null) continue;
                    const end = root.parseTimewEpoch(entry.end);
                    const date = Qt.formatDate(new Date(start * 1000), "yyyy-MM-dd");
                    if (!byDate[date]) byDate[date] = [];
                    byDate[date].push({
                        id: Number(entry.id) || 0,
                        startEpoch: start,
                        endEpoch: end,
                        open: end === null,
                        duration: root.formatDuration((end || now) - start)
                    });
                }
                for (const date in byDate) byDate[date].sort((a, b) => a.startEpoch - b.startEpoch);
                root.intervalsByDate = byDate;
            }
        }
    }

    Timer {
        interval: root.pollIntervalSec * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: isOnProc.running = true
    }

    function toggleTracking() {
        if (root.busy) return;
        root.busy = true;
        toggleProc.command = ["env", "TIMEWARRIORDB=" + root.timewarriorDb(), "@timew@", root.active ? "stop" : "start"];
        toggleProc.running = true;
    }

    Process {
        id: toggleProc
        onExited: exitCode => {
            root.busy = false;
            if (exitCode !== 0) {
                root.errorText = "Could not " + (root.active ? "stop" : "start") + " tracking";
                if (typeof ToastService !== "undefined") ToastService.showError("Timewarrior", root.errorText);
            } else {
                root.errorText = "";
            }
            isOnProc.running = true;
            root.refreshSummary();
        }
    }

    function normalizeTime(value) {
        const m = /^(\d{1,2}):(\d{2})$/.exec(String(value || "").trim());
        if (!m) return null;
        const h = Number(m[1]), min = Number(m[2]);
        if (h > 23 || min > 59) return null;
        return String(h).padStart(2, "0") + ":" + String(min).padStart(2, "0") + ":00";
    }

    function submitEdit(id, field, value) {
        const time = root.normalizeTime(value);
        root.editingCell = null;
        if (time === null) {
            root.errorText = "\"" + value + "\" is not a HH:MM time";
            if (typeof ToastService !== "undefined") ToastService.showError("Timewarrior", root.errorText);
            return;
        }
        root.busy = true;
        modifyProc.command = ["env", "TIMEWARRIORDB=" + root.timewarriorDb(), "@timew@", "rc.confirmation=off", "modify", field, "@" + id, time];
        modifyProc.running = true;
    }

    Process {
        id: modifyProc
        onExited: exitCode => {
            root.busy = false;
            if (exitCode !== 0 && typeof ToastService !== "undefined")
                ToastService.showError("Timewarrior", "Could not change the interval");
            root.refreshSummary();
        }
    }

    function deleteInterval(id) {
        root.pendingDeleteId = null;
        root.busy = true;
        deleteProc.command = ["env", "TIMEWARRIORDB=" + root.timewarriorDb(), "@timew@", "rc.confirmation=off", "delete", "@" + id];
        deleteProc.running = true;
    }

    Process {
        id: deleteProc
        onExited: exitCode => {
            root.busy = false;
            if (exitCode !== 0 && typeof ToastService !== "undefined")
                ToastService.showError("Timewarrior", "Could not delete the interval");
            root.refreshSummary();
        }
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

    // Right-click starts/stops without opening the popout, same intent as
    // bar.luau's `middle = "plugin ...:poller all toggle"` action -- adapted
    // to right-click since PluginComponent only exposes pillClickAction
    // (left, reserved here for the default open-popout behavior) and
    // pillRightClickAction, no middle-click hook.
    pillRightClickAction: () => root.toggleTracking()

    popoutWidth: 460
    popoutHeight: 640

    popoutContent: Component {
        PopoutComponent {
            id: popoutColumn

            headerText: "Timewarrior"
            detailsText: root.active ? ("Tracking for " + root.durationText) : "Not tracking"
            showCloseButton: true

            Component.onCompleted: {
                root.selectedDate = "";
                root.editingCell = null;
                root.pendingDeleteId = null;
                root.refreshSummary();
            }

            Connections {
                target: parentPopout
                function onOpened() {
                    root.selectedDate = "";
                    root.editingCell = null;
                    root.pendingDeleteId = null;
                    root.refreshSummary();
                }
            }

            DankButton {
                width: parent.width
                height: 40
                text: root.busy ? (root.active ? "Stopping…" : "Starting…") : (root.active ? "Stop" : "Start")
                iconName: root.active ? "stop" : "play_arrow"
                enabled: !root.busy
                onClicked: root.toggleTracking()
            }

            StyledText {
                visible: root.errorText !== ""
                text: root.errorText
                color: Theme.error
                font.pixelSize: Theme.fontSizeSmall
                width: parent.width
                wrapMode: Text.WordWrap
                topPadding: Theme.spacingXS
            }

            Item { width: parent.width; height: Theme.spacingS }
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

            // Selected day's intervals: id, start (click to edit), end
            // (click to edit, or "running"), duration, delete. Mirrors
            // panel.luau's intervalRow()/timeCell().
            Item { width: parent.width; height: Theme.spacingM }
            Row {
                width: parent.width
                StyledText {
                    text: root.activeDate() === root.todayDate ? "Today" : root.weekdayFor(root.activeDate()) + " " + root.activeDate()
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Bold
                    color: Theme.surfaceText
                    width: parent.width - (backToToday.visible ? backToToday.width : 0)
                }
                DankButton {
                    id: backToToday
                    visible: root.activeDate() !== root.todayDate
                    text: "Today"
                    iconName: "undo"
                    height: 24
                    onClicked: {
                        root.selectedDate = "";
                        root.editingCell = null;
                        root.pendingDeleteId = null;
                    }
                }
            }

            Column {
                width: parent.width
                spacing: Theme.spacingXS
                visible: root.rowsForActiveDate().length > 0

                Repeater {
                    model: root.rowsForActiveDate()

                    Row {
                        width: parent.width
                        height: 26
                        spacing: Theme.spacingXS
                        required property var modelData

                        StyledText {
                            width: 28
                            text: "@" + modelData.id
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                            horizontalAlignment: Text.AlignRight
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        // Start time: label, or an edit field when clicked.
                        Loader {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 60
                            property var row: parent.modelData
                            property string field: "start"
                            sourceComponent: (root.editingCell && root.editingCell.id === row.id && root.editingCell.field === field)
                                ? editFieldComponent : timeLabelComponent
                        }

                        StyledText {
                            text: "→"
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            visible: parent.modelData.open
                            width: 60
                            text: "running"
                            color: Theme.primary
                            font.pixelSize: Theme.fontSizeSmall
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Loader {
                            visible: !parent.modelData.open
                            anchors.verticalCenter: parent.verticalCenter
                            width: 60
                            property var row: parent.modelData
                            property string field: "end"
                            sourceComponent: (root.editingCell && root.editingCell.id === row.id && root.editingCell.field === field)
                                ? editFieldComponent : timeLabelComponent
                        }

                        StyledText {
                            text: modelData.duration
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeSmall
                            anchors.verticalCenter: parent.verticalCenter
                            horizontalAlignment: Text.AlignRight
                            width: parent.width - 28 - 60 - 14 - 60 - 24 - parent.spacing * 5
                        }

                        DankButton {
                            width: 24
                            height: 22
                            visible: root.pendingDeleteId !== modelData.id
                            iconName: "delete"
                            onClicked: root.pendingDeleteId = modelData.id
                        }
                        Row {
                            visible: root.pendingDeleteId === modelData.id
                            spacing: 2
                            DankButton {
                                width: 24
                                height: 22
                                iconName: "delete_forever"
                                onClicked: root.deleteInterval(modelData.id)
                            }
                            DankButton {
                                width: 24
                                height: 22
                                iconName: "close"
                                onClicked: root.pendingDeleteId = null
                            }
                        }
                    }
                }
            }

            StyledText {
                visible: root.rowsForActiveDate().length === 0
                text: root.activeDate() === root.todayDate ? "Nothing tracked today" : "Nothing tracked that day"
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
            }

            StyledText {
                text: "Last " + root.breakdownDays + " days"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Bold
                color: Theme.surfaceText
                topPadding: Theme.spacingS
            }

            DankFlickable {
                width: parent.width
                height: 160
                contentWidth: width
                contentHeight: breakdownColumn.implicitHeight
                clip: true
                visible: root.weekDays.length > 0 || Object.keys(root.intervalsByDate).length > 0

                Column {
                    id: breakdownColumn
                    width: parent.width
                    spacing: Theme.spacingXS

                    Repeater {
                        // Newest first, from whichever days the export actually covered.
                        model: Object.keys(root.intervalsByDate).sort().reverse()

                        Rectangle {
                            required property string modelData
                            width: parent.width
                            height: 26
                            radius: Theme.cornerRadius / 2
                            color: modelData === root.activeDate() ? Theme.surfaceContainerHigh : "transparent"

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.selectedDate = (root.selectedDate === modelData) ? "" : modelData;
                                    root.editingCell = null;
                                    root.pendingDeleteId = null;
                                }
                            }

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spacingXS
                                anchors.rightMargin: Theme.spacingXS

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.weekdayFor(modelData) + " " + modelData + (modelData === root.todayDate ? "  •" : "")
                                    color: modelData === root.activeDate() ? Theme.surfaceText : Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall
                                    width: parent.width - 60
                                }

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 60
                                    horizontalAlignment: Text.AlignRight
                                    text: {
                                        let total = 0;
                                        const rows = root.intervalsByDate[modelData] || [];
                                        for (let i = 0; i < rows.length; i++) {
                                            const r = rows[i];
                                            total += (r.open ? Math.floor(Date.now() / 1000) : r.endEpoch) - r.startEpoch;
                                        }
                                        return root.formatDuration(total);
                                    }
                                    color: Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeSmall
                                }
                            }
                        }
                    }
                }
            }

            StyledText {
                visible: Object.keys(root.intervalsByDate).length === 0
                text: "No tracked time in this window"
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
                bottomPadding: Theme.spacingS
            }

            Component {
                id: timeLabelComponent
                Rectangle {
                    property var row: parent && parent.row
                    property string field: parent ? parent.field : ""
                    width: 60
                    height: 22
                    color: "transparent"
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.pendingDeleteId = null;
                            root.editingCell = { id: row.id, field: field };
                        }
                    }
                    StyledText {
                        anchors.centerIn: parent
                        text: root.clockText(field === "start" ? row.startEpoch : row.endEpoch)
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                    }
                }
            }

            Component {
                id: editFieldComponent
                Row {
                    property var row: parent && parent.row
                    property string field: parent ? parent.field : ""
                    spacing: 2
                    DankTextField {
                        id: editField
                        width: 48
                        height: 22
                        text: root.clockText(field === "start" ? row.startEpoch : row.endEpoch)
                        Component.onCompleted: forceActiveFocus()
                        Keys.onReturnPressed: root.submitEdit(row.id, field, text)
                        Keys.onEnterPressed: root.submitEdit(row.id, field, text)
                        Keys.onEscapePressed: root.editingCell = null
                    }
                    DankButton {
                        width: 20
                        height: 22
                        iconName: "close"
                        onClicked: root.editingCell = null
                    }
                }
            }
        }
    }
}
