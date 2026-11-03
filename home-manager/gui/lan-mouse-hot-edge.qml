import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Hot edge: offers to start lan-mouse (locally and on the peers) when the
// pointer is pushed against the left or right edge (LAN_MOUSE_HOT_EDGE) of the
// outermost screen on that side and lan-mouse can't take it there, because
//  - the local daemon is not running, or
//  - the local daemon runs but the peer does not answer: lan-mouse reports a
//    handoff that stays pending (it connects lazily, so "connected" alone says
//    nothing until a crossing was attempted) and releases the pointer again.
// In both cases an invisible strip then takes over the middle of the edge, and
// the offer appears once the pointer has rested against it for a while.
ShellRoot {
    id: root

    readonly property bool onLeft: Quickshell.env("LAN_MOUSE_HOT_EDGE") === "left"

    // Noctalia palette (Indigo).
    readonly property color cPrimary: "#b6c4ff"
    readonly property color cSecondary: "#c3c5dd"
    readonly property color cTertiary: "#e4bad9"

    property bool lanMouseActive: true
    property bool offerVisible: false
    // Set after a failed handoff; cleared by a successful one, by starting
    // lan-mouse from here, or after a while so lan-mouse gets to retry.
    property bool peerDown: false
    // "local": lan-mouse is not running here; "peer": the peer did not answer.
    property string reason: "local"
    // "idle" | "starting" | "done" | "failed"
    property string phase: "idle"

    readonly property var edgeScreen: {
        let best = null
        for (const s of Quickshell.screens) {
            if (best === null
                    || (root.onLeft ? s.x < best.x : s.x + s.width > best.x + best.width))
                best = s
        }
        return best
    }

    function offer(why, hold) {
        if (root.phase === "starting" || suppressTimer.running)
            return
        root.reason = why
        root.phase = "idle"
        root.offerVisible = true
        hideTimer.interval = hold
        hideTimer.restart()
    }

    function dismiss() {
        root.offerVisible = false
        hideTimer.stop()
    }

    function handleState(line) {
        let state
        try {
            state = JSON.parse(line)
        } catch (e) {
            return
        }
        if (state.outgoing) {
            // A handoff went through: the peer is fine.
            pendingTimer.stop()
            root.peerDown = false
            if (root.reason === "peer" && root.phase === "idle")
                root.dismiss()
            return
        }
        if (state.pending && !root.peerDown && !pendingTimer.running)
            pendingTimer.restart()
    }

    Process {
        id: probe
        command: ["systemctl", "--user", "is-active", "--quiet", "lan-mouse.service"]
        onExited: (code, status) => {
            root.lanMouseActive = code === 0
            if (root.lanMouseActive && root.reason === "local" && root.phase === "idle")
                root.dismiss()
            if (root.lanMouseActive && !watcher.running)
                watcher.running = true
        }
    }

    // Snapshots arrive on every routing change (and whenever any frontend asks).
    Process {
        id: watcher
        command: ["lan-mouse", "cli", "input-state", "--watch"]
        stdout: SplitParser {
            onRead: data => root.handleState(data)
        }
    }

    // One fresh snapshot, shortly after a crossing that did not go through.
    Process {
        id: confirm
        command: ["lan-mouse", "cli", "input-state"]
        stdout: SplitParser {
            onRead: data => {
                let state
                try {
                    state = JSON.parse(data)
                } catch (e) {
                    return
                }
                const connected = (state.peers || []).some(p => p.active && p.connected)
                if (!state.outgoing && !connected) {
                    root.peerDown = true
                    peerDownTimer.restart()
                }
            }
        }
    }

    // A lazily connecting but alive peer answers within milliseconds; give it
    // a moment before declaring it asleep.
    Timer {
        id: pendingTimer
        interval: 1200
        onTriggered: confirm.running = true
    }

    Process {
        id: starter
        command: ["zsh", "-fc", "fpath=(/etc/profiles/per-user/$USER/share/zsh/site-functions $fpath); autoload -Uz lan-mouse::start lan-mouse::_control; lan-mouse::start"]
        onExited: (code, status) => {
            root.phase = code === 0 ? "done" : "failed"
            if (code === 0)
                root.peerDown = false
            hideTimer.interval = code === 0 ? 1400 : 3500
            hideTimer.restart()
            suppressTimer.restart()
            probe.running = true
        }
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: probe.running = true
    }

    Timer {
        id: hideTimer
        interval: 1500
        onTriggered: {
            root.offerVisible = false
            if (root.phase !== "starting")
                root.phase = "idle"
        }
    }

    Timer {
        id: peerDownTimer
        interval: 60000
        onTriggered: root.peerDown = false
    }

    // The pointer has to rest against the edge this long before the offer.
    Timer {
        id: dwellTimer
        interval: 1000
        onTriggered: root.offer(root.lanMouseActive ? "peer" : "local", 2500)
    }

    // Right after starting, the first crossing may still race the connection.
    Timer {
        id: suppressTimer
        interval: 4000
    }

    // Invisible strip on the middle of the edge. Only while lan-mouse can't
    // take the pointer anyway, so it never competes with a working handoff.
    PanelWindow {
        screen: root.edgeScreen
        visible: root.edgeScreen !== null && (!root.lanMouseActive || root.peerDown)
        onVisibleChanged: if (!visible) dwellTimer.stop()
        anchors { left: root.onLeft; right: !root.onLeft }
        implicitWidth: 2
        // Middle half of the edge; unanchored vertically means centered.
        implicitHeight: Math.round(root.edgeScreen.height * 0.5)
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "lan-mouse-hot-edge"

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: dwellTimer.restart()
            onExited: dwellTimer.stop()
        }
    }

    // A single glowing tab docked to the edge: its flat side is the screen
    // border, as if it pushed through from the peer's display next door.
    PanelWindow {
        id: offerWindow

        // 0 = tucked behind the edge, 1 = fully out. OutBack overshoots a bit.
        property real reveal: root.offerVisible ? 1 : 0
        Behavior on reveal {
            NumberAnimation {
                duration: root.offerVisible ? 520 : 280
                easing.type: root.offerVisible ? Easing.OutBack : Easing.InCubic
                easing.overshoot: 2.2
            }
        }

        readonly property bool animating: visible
        readonly property bool busy: root.phase === "starting"
        readonly property color glyphColor: root.phase === "failed" ? "#ffb4ab" : root.cPrimary

        screen: root.edgeScreen
        visible: root.edgeScreen !== null && reveal > 0.001
        anchors { left: root.onLeft; right: !root.onLeft }
        // Just large enough for the tab, the seam and the sparkles.
        implicitWidth: 80
        implicitHeight: 112
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "lan-mouse-hot-edge-offer"
        // The whole overlay is clickable, minus the outermost pixels so
        // lan-mouse's own 1px capture strip on the edge keeps working.
        mask: Region { item: area }

        Item {
            id: stage
            anchors.fill: parent

            // Sparkles streaming in from the other display.
            Repeater {
                model: 8
                Rectangle {
                    id: spark
                    required property int index
                    readonly property real seed: (index * 0.6180339887) % 1
                    property real t: seed
                    width: 2 + (index % 2)
                    height: width
                    radius: width / 2
                    color: [root.cPrimary, root.cTertiary, root.cSecondary, "#ffffff"][index % 4]
                    readonly property real reach: 30 + spark.seed * 34
                    x: (root.onLeft ? t * reach : stage.width - t * reach) - width / 2
                    y: stage.height / 2 + (spark.seed - 0.5) * 70 + Math.sin(t * Math.PI * 2 + index) * 4 - height / 2
                    scale: Math.sin(t * Math.PI) * 1.3
                    NumberAnimation on t {
                        loops: Animation.Infinite
                        running: offerWindow.animating
                        from: 0
                        to: 1
                        duration: 1100 + spark.seed * 1400
                    }
                }
            }

            Item {
                id: card
                width: 56
                height: 68
                // A round bulge sitting on the edge.
                readonly property real radius: height / 2
                // Centre of the bulge, relative to the card's centre.
                readonly property real bulgeOffset: (radius - width / 2) * (root.onLeft ? -1 : 1)
                anchors.verticalCenter: parent.verticalCenter
                // Slides out of the edge; never leaves it.
                x: root.onLeft
                    ? -(1 - offerWindow.reveal) * width
                    : parent.width - width * offerWindow.reveal
                transformOrigin: root.onLeft ? Item.Left : Item.Right
                scale: area.pressed ? 0.9 : (area.containsMouse ? 1.1 : 1)

                // Click: squash against the edge, then spring back out.
                property real pop: 0
                transform: Scale {
                    origin.x: root.onLeft ? 0 : card.width
                    origin.y: card.height / 2
                    xScale: 1 - card.pop * 0.3
                    yScale: 1 + card.pop * 0.18
                }
                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }

                property real spin: 0
                NumberAnimation on spin {
                    loops: Animation.Infinite
                    running: offerWindow.animating
                    from: 0
                    to: Math.PI * 2
                    duration: offerWindow.busy ? 800 : 3200
                }
                // Solid body with a rotating rainbow rim.
                Canvas {
                    id: frame
                    anchors.fill: parent
                    renderStrategy: Canvas.Cooperative
                    onPaint: {
                        const ctx = getContext("2d")
                        const w = width, h = height, r = card.radius, b = 1.5
                        ctx.reset()
                        // Drawn for the right edge, mirrored for the left.
                        if (root.onLeft) {
                            ctx.translate(w, 0)
                            ctx.scale(-1, 1)
                        }
                        // Rounded on the inside, flat (and open) on the edge.
                        // A half-round drop: round on the inside, flat (and
                        // open) where it meets the screen edge.
                        const cx = r, cy = h / 2, R = r - b
                        function tab(close) {
                            ctx.beginPath()
                            ctx.moveTo(w + 1, b)
                            ctx.lineTo(cx, b)
                            ctx.arc(cx, cy, R, -Math.PI / 2, Math.PI / 2, true)
                            ctx.lineTo(w + 1, h - b)
                            if (close)
                                ctx.closePath()
                        }

                        tab(true)
                        const body = ctx.createLinearGradient(0, 0, w, h)
                        body.addColorStop(0, area.containsMouse ? "#3a3b4d" : "#2c2d3a")
                        body.addColorStop(1, area.containsMouse ? "#242533" : "#1a1b23")
                        ctx.fillStyle = body
                        ctx.fill()

                        tab(false)
                        const rim = ctx.createConicalGradient(cx, cy, card.spin)
                        rim.addColorStop(0.00, root.cPrimary)
                        rim.addColorStop(0.25, root.cTertiary)
                        rim.addColorStop(0.50, "#7f8fff")
                        rim.addColorStop(0.75, root.cSecondary)
                        rim.addColorStop(1.00, root.cPrimary)
                        ctx.lineWidth = b
                        ctx.strokeStyle = rim
                        ctx.stroke()
                    }
                    Connections {
                        target: card
                        function onSpinChanged() { frame.requestPaint() }
                    }
                }

                // Moons orbiting the glyph.
                Item {
                    id: orbit
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: card.bulgeOffset
                    width: 46
                    height: 46
                    RotationAnimation on rotation {
                        loops: Animation.Infinite
                        running: offerWindow.animating
                        from: 0
                        to: 360
                        duration: offerWindow.busy ? 650 : 2600
                    }
                    Repeater {
                        model: 3
                        Rectangle {
                            required property int index
                            readonly property real a: index * Math.PI * 2 / 3
                            width: 3.5 - index * 0.5
                            height: width
                            radius: width / 2
                            color: [root.cPrimary, root.cTertiary, "#ffffff"][index]
                            x: orbit.width / 2 + Math.cos(a) * 19 - width / 2
                            y: orbit.height / 2 + Math.sin(a) * 19 - height / 2
                        }
                    }
                }

                // Mouse glyph: body, left button, rolling wheel.
                Rectangle {
                    id: glyph
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: card.bulgeOffset
                    width: 18
                    height: 27
                    radius: 9
                    color: "transparent"
                    border.color: offerWindow.glyphColor
                    border.width: 1.5
                    visible: root.phase !== "done"
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    Rectangle {
                        x: 1.5; y: 1.5
                        width: 5; height: 7
                        topLeftRadius: 5
                        color: root.cPrimary
                        visible: area.pressed || offerWindow.busy
                    }

                    Rectangle {
                        x: 5.75
                        width: 1.5
                        height: 4
                        radius: 0.75
                        color: root.cTertiary
                        property real roll: 0
                        y: 3 + roll * 3
                        SequentialAnimation on roll {
                            loops: Animation.Infinite
                            running: offerWindow.animating
                            NumberAnimation { to: 1; duration: offerWindow.busy ? 180 : 550; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 0; duration: offerWindow.busy ? 180 : 550; easing.type: Easing.InOutSine }
                        }
                    }

                    SequentialAnimation on scale {
                        loops: Animation.Infinite
                        running: offerWindow.animating
                        NumberAnimation { to: 1.1; duration: 700; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: card.bulgeOffset
                    visible: root.phase === "done"
                    text: "✓"
                    color: root.cPrimary
                    font.pixelSize: 18
                    font.weight: Font.Black
                    scale: visible ? 1 : 0.2
                    Behavior on scale { NumberAnimation { duration: 380; easing.type: Easing.OutBack; easing.overshoot: 3 } }
                }
            }

            // Sparks bursting out of the drop on click; some fly on into
            // the other display.
            Repeater {
                model: 12
                Rectangle {
                    required property int index
                    readonly property real a: index * Math.PI * 2 / 12
                    readonly property real dist: 10 + burst.progress * (34 + (index % 3) * 8)
                    width: 4 - (index % 2)
                    height: width
                    radius: width / 2
                    color: [root.cPrimary, root.cTertiary, root.cSecondary, "#ffffff"][index % 4]
                    visible: burst.progress > 0 && burst.progress < 1
                    x: card.x + card.width / 2 + card.bulgeOffset + Math.cos(a) * dist - width / 2
                    y: card.y + card.height / 2 + Math.sin(a) * dist - height / 2
                    scale: 1.6 * (1 - burst.progress)
                }
            }

            QtObject {
                id: burst
                property real progress: 0
            }

            ParallelAnimation {
                id: clickAnim
                SequentialAnimation {
                    NumberAnimation { target: card; property: "pop"; to: 1; duration: 110; easing.type: Easing.OutQuad }
                    NumberAnimation { target: card; property: "pop"; to: 0; duration: 700; easing.type: Easing.OutElastic; easing.amplitude: 1.2; easing.period: 0.35 }
                }
                NumberAnimation { target: burst; property: "progress"; from: 0; to: 1; duration: 650; easing.type: Easing.OutCubic }
                NumberAnimation { target: glyph; property: "rotation"; from: 0; to: root.onLeft ? -360 : 360; duration: 700; easing.type: Easing.OutBack }
            }

            MouseArea {
                id: area
                anchors.fill: parent
                anchors.leftMargin: root.onLeft ? 3 : 0
                anchors.rightMargin: root.onLeft ? 0 : 3
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: frame.requestPaint()
                onEntered: hideTimer.stop()
                onExited: if (!offerWindow.busy) hideTimer.restart()
                onClicked: {
                    if (starter.running)
                        return
                    clickAnim.restart()
                    root.phase = "starting"
                    hideTimer.stop()
                    starter.running = true
                }
            }
        }
    }
}
