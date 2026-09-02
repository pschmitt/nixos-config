pragma Singleton
import QtQuick

QtObject {
    // Palette lifted from waybar/style.css for visual continuity.
    readonly property color bg: "#191818"
    readonly property color text: "#d2d2d2"
    readonly property color muted: "#a9a9a9"
    readonly property color accent: "#7186b2"
    readonly property color alert: "#e27978"
    readonly property color warn: "#ffab00"
    readonly property color ok: "#7ab87a"
    readonly property color idleActive: "#8d70b3"

    readonly property string fontFamily: "ComicCode Nerd Font"
    readonly property int fontSize: 13
    readonly property int fontWeight: Font.Black

    readonly property int barHeight: 26
    readonly property int barMargin: 4
    readonly property int barRadius: 11
    readonly property int pillRadius: 8
    readonly property int pillSpacing: 2
    readonly property int pillPad: 6

    readonly property int animFast: 120
    readonly property int animNormal: 220
    readonly property int animSlow: 420
    readonly property int easing: Easing.OutCubic
}
