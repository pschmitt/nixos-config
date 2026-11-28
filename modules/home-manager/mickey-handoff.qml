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
        duration: 360
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
                width: 344
                height: 344
                onPhaseChanged: requestPaint()
                onPointChanged: requestPaint()
                onAvailableChanged: if (available) requestPaint()

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    if (!point)
                        return

                    const arriving = point.kind === "arrive"
                    const accent = arriving ? "#43dcff" : "#a486ff"
                    const light = arriving ? "#c5fff3" : "#eedaff"
                    const takeoff = 0.46
                    const travel = arriving ? 1 - Math.pow(1 - phase, 3)
                                            : Math.pow(Math.min(phase / takeoff, 1), 1.6)
                    const head = arriving ? -8 + 104 * travel : 72 - 128 * travel
                    const tail = head + (arriving ? -1 : 1) * (32 + 45 * Math.sin(Math.PI * phase))
                    const fade = Math.min(1, phase * 14) * Math.pow(1 - phase, 0.76)

                    ctx.save()
                    ctx.translate(width / 2, height / 2)
                    ctx.rotate(point.angle)
                    ctx.lineCap = "round"

                    // The bright core and its tapered trail move along the edge normal.
                    const streak = ctx.createLinearGradient(tail, 0, head, 0)
                    streak.addColorStop(0, "transparent")
                    streak.addColorStop(0.55, accent)
                    streak.addColorStop(0.88, light)
                    streak.addColorStop(1, "#ffffff")
                    for (const [weight, opacity] of [[20, 0.13], [8, 0.36], [2.2, 0.98]]) {
                        ctx.globalAlpha = fade * opacity
                        ctx.strokeStyle = streak
                        ctx.lineWidth = weight
                        ctx.beginPath()
                        ctx.moveTo(tail, 0)
                        ctx.lineTo(head, 0)
                        ctx.stroke()
                    }

                    const core = ctx.createRadialGradient(head, 0, 0, head, 0, 16)
                    core.addColorStop(0, "#ffffff")
                    core.addColorStop(0.19, light)
                    core.addColorStop(0.45, accent)
                    core.addColorStop(1, "transparent")
                    ctx.globalAlpha = fade
                    ctx.fillStyle = core
                    ctx.fillRect(head - 16, -16, 32, 32)

                    // Contact lights the seam briefly, then scatters along the edge.
                    const contact = arriving ? 0.03 : takeoff * Math.pow(72 / 128, 1 / 1.6)
                    const flash = Math.max(0, 1 - Math.abs(phase - contact) * 7)
                    const span = 17 + 33 * flash
                    const seam = ctx.createLinearGradient(0, -span, 0, span)
                    seam.addColorStop(0, "transparent")
                    seam.addColorStop(0.5, light)
                    seam.addColorStop(1, "transparent")
                    ctx.globalAlpha = flash * 0.9
                    ctx.fillStyle = seam
                    ctx.fillRect(0, -span, 2.5, span * 2)

                    ctx.strokeStyle = accent
                    for (let i = 0; i < 9; ++i) {
                        const age = phase - contact - i * 0.018
                        if (age < 0 || age > 0.46)
                            continue

                        const side = i % 2 === 0 ? 1 : -1
                        const x = 4 + age * (26 + i * 9)
                        const y = side * (3 + age * (44 + (i * 19) % 105))
                        ctx.globalAlpha = 0.8 * (1 - age / 0.46)
                        ctx.lineWidth = i % 3 === 0 ? 2 : 1.1
                        ctx.beginPath()
                        ctx.moveTo(x, y)
                        ctx.lineTo(x + 3 + age * 13, y + side * 3)
                        ctx.stroke()
                    }
                    ctx.restore()
                }
            }
        }
    }
}
