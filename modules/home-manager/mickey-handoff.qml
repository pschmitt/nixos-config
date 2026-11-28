import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    property var handoff: null
    property var away: null
    property real progress: 1
    property string lastEvent: ""

    function duration(style) {
        switch (style) {
        case "fold": return 280
        case "wave": return 340
        case "prism": return 320
        case "edge-pulse": return 190
        case "comet": return 290
        case "wormhole": return 720
        case "echo": return 390
        case "scan": return 300
        default: return 0
        }
    }

    function paintVariant(ctx, id, p, incoming) {
        const clamp = (n) => Math.max(0, Math.min(1, n))
        const ease = (n) => 1 - (1 - n) ** 3
        const colors = {
            violet: "#ba9aff",
            cyan: "#75f5ec",
            white: "#efffff",
            rose: "#ff9cce",
            gold: "#ffd29d",
        }
        function line(points, color, size, alpha) {
            ctx.globalAlpha = clamp(alpha)
            ctx.strokeStyle = color
            ctx.lineWidth = size
            ctx.lineCap = "round"
            ctx.beginPath()
            points.forEach(([x, y], i) => (i ? ctx.lineTo(x, y) : ctx.moveTo(x, y)))
            ctx.stroke()
        }
        function dot(x, y, r, color, alpha) {
            ctx.globalAlpha = clamp(alpha)
            ctx.fillStyle = color
            ctx.beginPath()
            ctx.arc(x, y, r, 0, Math.PI * 2)
            ctx.fill()
        }
        function shape(points, color, alpha) {
            ctx.globalAlpha = clamp(alpha)
            ctx.fillStyle = color
            ctx.beginPath()
            points.forEach(([x, y], i) => (i ? ctx.lineTo(x, y) : ctx.moveTo(x, y)))
            ctx.closePath()
            ctx.fill()
        }
        function ellipseArc(x, y, rx, ry, rotation, from, to) {
            ctx.save()
            ctx.translate(x, y)
            ctx.rotate(rotation)
            ctx.scale(rx, ry)
            ctx.beginPath()
            ctx.arc(0, 0, 1, from, to)
            ctx.restore()
            ctx.stroke()
        }
        if (p <= 0 || p >= 1) return
        const tint = incoming ? colors.cyan : colors.violet,
            light = colors.white,
            q = ease(p)
        const fade = Math.min(1, p * 14) * (1 - p) ** 0.76
        switch (id) {
            case "fold": {
                const spread = incoming ? q : 1 - q,
                    x = 68 * spread,
                    y = 9 + 39 * Math.sin(p * Math.PI)
                shape(
                    [
                        [0, -y],
                        [x, -y * 0.55],
                        [x, 0],
                        [0, -4],
                    ],
                    tint,
                    fade * 0.42,
                )
                shape(
                    [
                        [0, -4],
                        [x, 0],
                        [x, y * 0.55],
                        [0, y],
                    ],
                    incoming ? "#39778b" : "#7151a7",
                    fade * 0.73,
                )
                line(
                    [
                        [0, -y],
                        [x, -y * 0.55],
                        [x, y * 0.55],
                        [0, y],
                    ],
                    tint,
                    1.7,
                    fade,
                )
                line(
                    [
                        [0, -y],
                        [0, y],
                    ],
                    light,
                    2,
                    fade * 0.7,
                )
                break
            }
            case "wave":
                for (let i = 0; i < 3; i++) {
                    const age = clamp(p - i * 0.12)
                    if (!age) continue
                    const x = 8 + 90 * ease(age),
                        radius = 10 + 52 * age
                    ctx.globalAlpha = (1 - age) ** 2 * 0.8
                    ctx.strokeStyle = i === 0 ? light : tint
                    ctx.lineWidth = 2.6 - i * 0.55
                    ellipseArc(
                        incoming ? x : 108 - x,
                        0,
                        radius * 0.37,
                        radius,
                        0,
                        -Math.PI / 2,
                        Math.PI / 2,
                    )
                }
                break
            case "prism":
                ;[colors.rose, colors.gold, tint].forEach((color, i) => {
                    const x = (incoming ? q : 1 - q) * (28 + 26 * i),
                        y = (i - 1) * 34 * Math.sin(Math.PI * p)
                    shape(
                        [
                            [0, 0],
                            [x, y - 6],
                            [x + 16, y],
                            [x, y + 6],
                        ],
                        color,
                        fade * 0.53,
                    )
                    line(
                        [
                            [0, 0],
                            [x + 16, y],
                        ],
                        color,
                        1.4,
                        fade,
                    )
                })
                break
            case "wormhole": {
                const open = clamp(Math.min(p / 0.19, (1 - p) / 0.31))
                const aperture = 8 + 50 * ease(open)
                const twist = p * Math.PI * 3 + (incoming ? 0 : Math.PI)
                const halo = ctx.createRadialGradient(0, 0, 3, 0, 0, aperture * 1.6)
                halo.addColorStop(0, "#100a20")
                halo.addColorStop(0.42, "#382058")
                halo.addColorStop(0.64, tint)
                halo.addColorStop(1, "transparent")
                dot(0, 0, aperture * 1.6, halo, open * 0.58)

                // Nested turning rings deepen toward the seam.
                for (let ring = 5; ring >= 0; ring--) {
                    const depth = ring / 5,
                        radius = aperture * (1 - depth * 0.83)
                    const shift =
                        depth * (incoming ? 1 : -1) * 19 * Math.sin(p * Math.PI)
                    for (let arc = 0; arc < 3; arc++) {
                        const angle = twist + (arc * Math.PI * 2) / 3 + depth * 0.9
                        ctx.globalAlpha = open * (0.49 - depth * 0.23)
                        ctx.strokeStyle = [tint, colors.rose, colors.gold][arc]
                        ctx.lineWidth = 2.7 - depth * 1.5
                        ellipseArc(
                            shift,
                            0,
                            radius * 0.72,
                            radius,
                            depth * 0.33,
                            angle,
                            angle + 1.75,
                        )
                    }
                }
                for (let i = 0; i < 32; i++) {
                    const angle = i * 2.39996 + twist * 0.36
                    const travel = (p * 1.9 + i * 0.137) % 1,
                        r = aperture * (0.24 + travel * 1.65)
                    const x = Math.cos(angle) * r,
                        y = Math.sin(angle) * r
                    const alpha = Math.sin(travel * Math.PI) * open
                    line(
                        [
                            [x * 0.82, y * 0.82],
                            [x, y],
                        ],
                        i % 4 ? tint : colors.gold,
                        1 + (i % 3) * 0.45,
                        alpha * 0.77,
                    )
                }
                const flash = clamp(1 - Math.abs(p - (incoming ? 0.13 : 0.27)) * 9)
                line(
                    [
                        [0, -aperture * 1.24],
                        [0, aperture * 1.24],
                    ],
                    light,
                    1.6,
                    flash * 0.85,
                )
                dot(0, 0, flash * 10, light, flash * 0.72)
                break
            }
            case "echo": {
                for (let i = 4; i >= 0; i--) {
                    const age = clamp((p - i * 0.09) * 1.4)
                    if (!age || age === 1) continue
                    const x = 8 + 79 * (incoming ? ease(age) : 1 - ease(age))
                    const y = Math.sin(age * Math.PI) * (i % 2 ? 1 : -1) * i * 5
                    const opacity = Math.sin(age * Math.PI) * (1 - i * 0.13)
                    shape(
                        [
                            [x, y],
                            [x + 14, y + 9],
                            [x + 7, y + 10],
                            [x + 4, y + 16],
                        ],
                        tint,
                        opacity * 0.21,
                    )
                    line(
                        [
                            [x + 4, y + 16],
                            [x, y],
                            [x + 14, y + 9],
                        ],
                        i ? tint : light,
                        1.4,
                        opacity * 0.85,
                    )
                }
                break
            }
            case "scan": {
                const x = (incoming ? q : 1 - q) * 74,
                    spread = 20 + 34 * Math.sin(p * Math.PI)
                const beam = ctx.createLinearGradient(0, -spread, 0, spread)
                beam.addColorStop(0, "transparent")
                beam.addColorStop(0.5, light)
                beam.addColorStop(1, "transparent")
                shape(
                    [
                        [x - 11, -spread],
                        [x, -spread],
                        [x, spread],
                        [x - 11, spread],
                    ],
                    tint,
                    fade * 0.19,
                )
                line(
                    [
                        [x, -spread],
                        [x, spread],
                    ],
                    beam,
                    2.2,
                    fade,
                )
                for (let i = 0; i < 9; i++) {
                    const y = (i - 4) * 9,
                        width = 7 + ((i * 13) % 22) * Math.sin(p * Math.PI)
                    line(
                        [
                            [x - width, y],
                            [x + 0.8, y],
                        ],
                        tint,
                        1,
                        fade * (1 - Math.abs(i - 4) * 0.15),
                    )
                }
                break
            }
            case "edge-pulse": {
                const y = 11 + 30 * q,
                    x = 2 + 14 * q
                line(
                    [
                        [x, -y],
                        [x, y],
                    ],
                    tint,
                    2.3,
                    fade,
                )
                line(
                    [
                        [x, -y],
                        [x + 9, -y],
                    ],
                    tint,
                    1.4,
                    fade * 0.8,
                )
                line(
                    [
                        [x, y],
                        [x + 9, y],
                    ],
                    tint,
                    1.4,
                    fade * 0.8,
                )
                dot(3, 0, 3.6, light, fade)
                break
            }
            case "comet":
                for (let i = 0; i < 3; i++) {
                    const age = clamp((p - i * 0.08) / 0.84)
                    if (!age) continue
                    const x = 3 + 74 * (incoming ? ease(age) : 1 - ease(age)),
                        y = (i - 1) * Math.sin(age * Math.PI) * 15
                    dot(x, y, 9 - i, tint, (1 - age) * 0.13)
                    dot(x, y, 3.7 - i * 0.65, i ? tint : light, (1 - age) * 0.95)
                }
                break
        }
    }

    function locate(event) {
        if (!event || !Number.isInteger(event.x) || !Number.isInteger(event.y))
            return null
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
                nearest = { "monitor": screen.name, "x": x, "y": y }
                const edges = [x, screen.width - 1 - x, y, screen.height - 1 - y]
                nearest.angle = [0, Math.PI, Math.PI / 2, -Math.PI / 2][edges.indexOf(Math.min(...edges))]
            }
        }

        return nearest
    }

    function show(event) {
        if ((event.kind !== "arrive" && event.kind !== "depart")
                || !Number.isInteger(event.x) || !Number.isInteger(event.y)
                || !Number.isFinite(event.time) || Date.now() - event.time > 600)
            return

        const key = event.time + ":" + event.sequence
        if (key === lastEvent)
            return
        lastEvent = key

        const nearest = locate(event)
        if (nearest) {
            nearest.kind = event.kind
            nearest.style = event.style
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

    FileView {
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/mickey-away.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                root.away = root.locate(JSON.parse(text()))
            } catch (error) {
                root.away = null
            }
        }
    }

    NumberAnimation {
        id: pulse
        target: root
        property: "progress"
        from: 0
        to: 1
        duration: root.duration(root.handoff?.style) || 360
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
                    if (root.duration(point.style) > 0) {
                        ctx.save()
                        ctx.translate(width / 2, height / 2)
                        ctx.rotate(point.angle)
                        root.paintVariant(ctx, point.style, phase, arriving)
                        ctx.restore()
                        return
                    }
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

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: awayWindow
            required property var modelData
            readonly property var point: root.away
            screen: modelData
            visible: point?.monitor === modelData.name
            implicitWidth: 28
            implicitHeight: 19
            anchors { top: true; left: true }
            margins {
                left: (point?.x ?? 0) > modelData.width - awayWindow.implicitWidth - 12
                      ? Math.max(0, point.x - awayWindow.implicitWidth - 8)
                      : (point?.x ?? 0) + 12
                top: Math.max(0, Math.min(modelData.height - awayWindow.implicitHeight, (point?.y ?? 0) + 8))
            }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            mask: Region {}
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.namespace: "mickey-away-cursor"

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: "#ec262239"
                border.color: "#baa3e8"
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: "zZ"
                    color: "#f1e6ff"
                    font.pixelSize: 11
                    font.bold: true
                }
            }
        }
    }
}
