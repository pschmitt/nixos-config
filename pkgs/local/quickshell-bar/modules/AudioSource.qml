import QtQuick
import Quickshell.Services.Pipewire
import "../" as Root
import "../widgets" as Widgets

Widgets.Pill {
    id: root
    readonly property PwNode source: Pipewire.defaultAudioSource

    PwObjectTracker {
        objects: [root.source]
    }

    onClicked: if (root.source?.ready) root.source.audio.muted = !root.source.audio.muted

    Text {
        color: (root.source?.audio && root.source.audio.muted) ? Root.Theme.alert : Root.Theme.text
        font.family: Root.Theme.fontFamily
        font.weight: Root.Theme.fontWeight
        font.pixelSize: Root.Theme.fontSize
        text: (root.source?.audio && root.source.audio.muted) ? " MUTED" : "󰍬"
    }
}
