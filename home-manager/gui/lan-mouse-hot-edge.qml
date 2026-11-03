import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Hot edge: offers to start lan-mouse (locally and on the peers) when the
// pointer is pushed against the left or right edge (LAN_MOUSE_HOT_EDGE) of the
// outermost screen on that side and lan-mouse can't take it there, because
//  - the local daemon is not running: an invisible strip on the edge notices
//    the pointer, or
//  - the local daemon runs but the peer does not answer: lan-mouse reports a
//    handoff that stays pending (it connects lazily, so "connected" alone says
//    nothing until a crossing was attempted) and releases the pointer again.
ShellRoot {
    id: root

    readonly property bool onLeft: Quickshell.env("LAN_MOUSE_HOT_EDGE") === "left"

    // Noctalia palette (Indigo).
    readonly property color cPrimary: "#b6c4ff"
    readonly property color cSecondary: "#c3c5dd"
    readonly property color cTertiary: "#e4bad9"

    property bool lanMouseActive: true
    property bool offerVisible: false
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
            if (root.reason === "peer" && root.phase === "idle")
                root.dismiss()
            return
        }
        if (state.pending && !pendingTimer.running && !root.offerVisible) {
            pendingTimer.restart()
        }
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
                if (!state.outgoing && !connected)
                    root.offer("peer", 4500)
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

    // Right after starting, the first crossing may still race the connection.
    Timer {
        id: suppressTimer
        interval: 4000
    }

    // Invisible strip on the middle of the edge. Only while lan-mouse is not
    // running, so it never competes with lan-mouse's own capture surfaces.
    PanelWindow {
        screen: root.edgeScreen
        visible: root.edgeScreen !== null && !root.lanMouseActive
        anchors { left: root.onLeft; right: !root.onLeft }
        implicitWidth: 2
        // Middle quarter of the edge; unanchored vertically means centered.
        implicitHeight: Math.round(root.edgeScreen.height * 0.25)
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "lan-mouse-hot-edge"

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: root.offer("local", 1800)
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
        implicitWidth: 72
        implicitHeight: 170
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "lan-mouse-hot-edge-offer"
        // Only the tab takes input, minus the outermost pixels so lan-mouse's
        // own 1px capture strip on the edge keeps working underneath.
        mask: Region { item: hitArea }

        Item {
            id: stage
            anchors.fill: parent
            opacity: Math.min(1, Math.max(0, offerWindow.reveal))

            QtObject {
                id: halo
                property real breath: 1
                SequentialAnimation on breath {
                    loops: Animation.Infinite
                    running: offerWindow.animating
                    NumberAnimation { to: offerWindow.busy ? 2.2 : 1.6; duration: 900; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 0.6; duration: 900; easing.type: Easing.InOutSine }
                }
            }

            readonly property real edgeX: root.onLeft ? 0 : width

            // Light leaking through a seam in the edge.
            Rectangle {
                width: 26
                height: 150 * Math.max(0, offerWindow.reveal)
                anchors.verticalCenter: parent.verticalCenter
                x: root.onLeft ? 0 : parent.width - width
                opacity: 0.35 * halo.breath
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: root.onLeft ? root.cPrimary : "transparent" }
                    GradientStop { position: 1; color: root.onLeft ? "transparent" : root.cPrimary }
                }
            }
            Rectangle {
                width: 2
                height: 150 * Math.max(0, offerWindow.reveal)
                anchors.verticalCenter: parent.verticalCenter
                x: root.onLeft ? 0 : parent.width - width
                gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 0.3; color: root.cTertiary }
                    GradientStop { position: 0.5; color: "#ffffff" }
                    GradientStop { position: 0.7; color: root.cPrimary }
                    GradientStop { position: 1; color: "transparent" }
                }
            }

            // Ripples spreading out of the edge, cut in half by it.
            Repeater {
                model: 3
                Rectangle {
                    id: wave
                    required property int index
                    property real cycle: 0
                    readonly property real t: (cycle + index / 3) % 1
                    width: 40 + t * 90
                    height: width
                    radius: width / 2
                    x: stage.edgeX - width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: "transparent"
                    border.width: 2
                    border.color: index % 2 === 0 ? root.cPrimary : root.cTertiary
                    opacity: (1 - t) * 0.45 * Math.min(1, halo.breath)
                    NumberAnimation on cycle {
                        loops: Animation.Infinite
                        running: offerWindow.animating
                        from: 0
                        to: 1
                        duration: offerWindow.busy ? 900 : 2400
                    }
                }
            }

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
                    opacity: Math.sin(t * Math.PI) * 0.95
                    scale: 1.3 - t * 0.7
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
                width: 40
                height: 50
                readonly property real radius: 15
                anchors.verticalCenter: parent.verticalCenter
                // Slides out of the edge; never leaves it.
                x: root.onLeft
                    ? -(1 - offerWindow.reveal) * width
                    : parent.width - width * offerWindow.reveal
                transformOrigin: root.onLeft ? Item.Left : Item.Right
                scale: area.pressed ? 0.9 : (area.containsMouse ? 1.1 : 1)
                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }

                property real spin: 0
                property real shimmer: -0.5
                NumberAnimation on spin {
                    loops: Animation.Infinite
                    running: offerWindow.animating
                    from: 0
                    to: Math.PI * 2
                    duration: offerWindow.busy ? 800 : 3200
                }
                SequentialAnimation on shimmer {
                    loops: Animation.Infinite
                    running: offerWindow.animating
                    NumberAnimation { from: -0.5; to: 1.5; duration: 900; easing.type: Easing.InOutQuad }
                    PauseAnimation { duration: 1600 }
                }

                // Glass body, shimmer sweep and a rotating rainbow rim.
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
                        function tab(close) {
                            ctx.beginPath()
                            ctx.moveTo(w + 1, b)
                            ctx.lineTo(r, b)
                            ctx.arcTo(b, b, b, r, r - b)
                            ctx.lineTo(b, h - r)
                            ctx.arcTo(b, h - b, r, h - b, r - b)
                            ctx.lineTo(w + 1, h - b)
                            if (close)
                                ctx.closePath()
                        }

                        tab(true)
                        const body = ctx.createLinearGradient(0, 0, w, h)
                        body.addColorStop(0, area.containsMouse ? "#f43a3b4d" : "#f02c2d3a")
                        body.addColorStop(1, area.containsMouse ? "#f8242533" : "#f41a1b23")
                        ctx.fillStyle = body
                        ctx.fill()

                        ctx.save()
                        ctx.clip()
                        const sheen = ctx.createLinearGradient(0, 0, 0, h * 0.5)
                        sheen.addColorStop(0, "#2cffffff")
                        sheen.addColorStop(1, "#00ffffff")
                        ctx.fillStyle = sheen
                        ctx.fillRect(0, 0, w, h * 0.5)
                        const sx = card.shimmer * w
                        const sweep = ctx.createLinearGradient(sx - 14, 0, sx + 14, h)
                        sweep.addColorStop(0, "#00ffffff")
                        sweep.addColorStop(0.5, "#40ffffff")
                        sweep.addColorStop(1, "#00ffffff")
                        ctx.fillStyle = sweep
                        ctx.fillRect(0, 0, w, h)
                        ctx.restore()

                        tab(false)
                        const rim = ctx.createConicalGradient(w / 2, h / 2, card.spin)
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

                Item {
                    id: hitArea
                    anchors.fill: parent
                    anchors.leftMargin: root.onLeft ? 3 : 0
                    anchors.rightMargin: root.onLeft ? 0 : 3
                }

                // Click ripple.
                Rectangle {
                    id: ripple
                    anchors.centerIn: parent
                    width: 0
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.color: root.cPrimary
                    border.width: 2
                    opacity: 0
                    ParallelAnimation {
                        id: rippleAnim
                        NumberAnimation { target: ripple; property: "width"; from: 10; to: 90; duration: 600; easing.type: Easing.OutCubic }
                        NumberAnimation { target: ripple; property: "opacity"; from: 0.8; to: 0; duration: 600; easing.type: Easing.OutCubic }
                    }
                }

                // Moons orbiting the glyph.
                Item {
                    id: orbit
                    anchors.centerIn: parent
                    width: 30
                    height: 30
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
                            x: orbit.width / 2 + Math.cos(a) * 14 - width / 2
                            y: orbit.height / 2 + Math.sin(a) * 14 - height / 2
                        }
                    }
                }

                // Mouse glyph: body, left button, rolling wheel.
                Rectangle {
                    anchors.centerIn: parent
                    width: 13
                    height: 19
                    radius: 6.5
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
                        opacity: area.pressed || offerWindow.busy ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 90 } }
                    }

                    Rectangle {
                        x: 5.75
                        width: 1.5
                        height: 4
                        radius: 0.75
                        color: root.cTertiary
                        property real roll: 0
                        y: 3 + roll * 3.5
                        opacity: 1 - roll
                        NumberAnimation on roll {
                            loops: Animation.Infinite
                            running: offerWindow.animating
                            from: 0
                            to: 1
                            duration: offerWindow.busy ? 350 : 1100
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
                    visible: root.phase === "done"
                    text: "✓"
                    color: root.cPrimary
                    font.pixelSize: 18
                    font.weight: Font.Black
                    scale: visible ? 1 : 0.2
                    Behavior on scale { NumberAnimation { duration: 380; easing.type: Easing.OutBack; easing.overshoot: 3 } }
                }

                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onContainsMouseChanged: frame.requestPaint()
                    onEntered: hideTimer.stop()
                    onExited: if (!offerWindow.busy) hideTimer.restart()
                    onClicked: {
                        if (starter.running)
                            return
                        rippleAnim.restart()
                        root.phase = "starting"
                        hideTimer.stop()
                        starter.running = true
                    }
                }
            }
        }
    }
}
