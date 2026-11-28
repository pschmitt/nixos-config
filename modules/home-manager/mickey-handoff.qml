import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    property var handoff: null
    property real progress: 1
    property string lastEvent: ""

    function show(event) {
        if ((event.kind !== "arrive" && event.kind !== "depart")
                || !Number.isInteger(event.x) || !Number.isInteger(event.y)
                || !Number.isFinite(event.time) || Date.now() - event.time > 600)
            return

        const key = event.time + ":" + event.sequence
        if (key === lastEvent)
            return
        lastEvent = key

        let nearest = null
        let distance = Infinity
        for (const screen of Quickshell.screens) {
            const x = Math.max(0, Math.min(screen.width - 1, event.x - screen.x))
            const y = Math.max(0, Math.min(screen.height - 1, event.y - screen.y))
            const dx = event.x - screen.x - x
            const dy = event.y - screen.y - y
            const error = dx * dx + dy * dy
            if (error < distance) {
                distance = error
                nearest = { "monitor": screen.name, "x": x, "y": y, "kind": event.kind }
                const edges = [x, screen.width - 1 - x, y, screen.height - 1 - y]
                nearest.angle = [0, Math.PI, Math.PI / 2, -Math.PI / 2][edges.indexOf(Math.min(...edges))]
            }
        }

        if (nearest) {
            handoff = nearest
            pulse.restart()
        }
    }

    FileView {
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/mickey-handoff.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.show(JSON.parse(text()))
            } catch (error) {
                // The file may be empty before the first crossing.
            }
        }
    }

    NumberAnimation {
        id: pulse
        target: root
        property: "progress"
        from: 0
        to: 1
        duration: 260
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData
            screen: modelData
            visible: pulse.running && root.handoff?.monitor === modelData.name
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            mask: Region {}
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.namespace: "mickey-handoff"

            Canvas {
                readonly property real phase: root.progress
                readonly property var point: root.handoff
                x: (point?.x ?? 0) - width / 2
                y: (point?.y ?? 0) - height / 2
                width: 220
                height: 220
                onPhaseChanged: requestPaint()
                onPointChanged: requestPaint()
                onAvailableChanged: if (available) requestPaint()

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    if (!point)
                        return

                    const arriving = point.kind === "arrive"
                    const spread = arriving ? 1 - Math.pow(1 - phase, 3) : Math.pow(1 - phase, 2)
                    const strength = Math.min(1, phase * 9) * Math.pow(1 - phase, 1.15)
                    ctx.save()
                    ctx.translate(width / 2, height / 2)
                    ctx.rotate(point.angle)
                    ctx.lineCap = "round"

                    // A broad, tinted sweep and two finer wavefronts.
                    ctx.scale(0.58, 1)
                    const radius = 7 + 79 * spread
                    const palette = arriving ? ["#58d9ff", "#c3fff1"] : ["#a785ff", "#e7d6ff"]
                    for (const [offset, weight, alpha, color] of [
                        [0, 17, 0.18, palette[0]],
                        [0, 5, 0.55, palette[0]],
                        [12, 1.6, 0.85, palette[1]]
                    ]) {
                        ctx.globalAlpha = strength * alpha
                        ctx.strokeStyle = color
                        ctx.lineWidth = weight
                        ctx.beginPath()
                        ctx.arc(0, 0, Math.max(3, radius - offset), -1.48, 1.48)
                        ctx.stroke()
                    }
                    ctx.restore()
                }
            }
        }
    }
}
