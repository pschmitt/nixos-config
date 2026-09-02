import QtQuick
import Quickshell.Services.Mpris
import "../" as Root
import "../widgets" as Widgets

Widgets.Pill {
    id: root
    readonly property MprisPlayer player: Mpris.players.values.length > 0 ? Mpris.players.values[0] : null
    collapsed: !root.player

    onClicked: root.player?.togglePlaying()

    Text {
        color: Root.Theme.text
        font.family: Root.Theme.fontFamily
        font.weight: Root.Theme.fontWeight
        font.pixelSize: Root.Theme.fontSize
        elide: Text.ElideRight
        width: Math.min(implicitWidth, 260)
        text: {
            if (!root.player) return "";
            const icon = root.player.isPlaying ? " " : " ";
            const track = root.player.trackArtist ? (root.player.trackArtist + " - " + root.player.trackTitle) : root.player.trackTitle;
            return icon + (track || root.player.identity);
        }
    }
}
