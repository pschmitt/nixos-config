import QtQuick
import Quickshell.Services.Pipewire
import "../" as Root
import "../widgets" as Widgets

Widgets.Pill {
    id: root
    readonly property PwNode sink: Pipewire.defaultAudioSink

    PwObjectTracker {
        objects: [root.sink]
    }

    onClicked: if (root.sink?.ready) root.sink.audio.muted = !root.sink.audio.muted
    onWheelUp: if (root.sink?.ready) root.sink.audio.volume = Math.min(1.5, root.sink.audio.volume + 0.05)
    onWheelDown: if (root.sink?.ready) root.sink.audio.volume = Math.max(0, root.sink.audio.volume - 0.05)

    Text {
        color: (root.sink?.audio && root.sink.audio.muted) ? Root.Theme.alert : Root.Theme.text
        font.family: Root.Theme.fontFamily
        font.weight: Root.Theme.fontWeight
        font.pixelSize: Root.Theme.fontSize
        text: {
            if (!root.sink?.ready || !root.sink.audio) return "󰕾 …";
            if (root.sink.audio.muted) return "󰝟 MUTE";
            const pct = Math.round(root.sink.audio.volume * 100);
            return (pct >= 60 ? "󰕾 " : pct > 0 ? "󰖀 " : "󰕿 ") + pct + "%";
        }
    }
}
