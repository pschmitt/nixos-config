import QtQuick
import Quickshell
import Quickshell.Io
import "../" as Root
import "../widgets" as Widgets

Widgets.Pill {
    id: root
    interactive: false
    collapsed: !root.active

    property bool active: false
    property string apps: ""

    Text {
        color: Root.Theme.alert
        font.family: Root.Theme.fontFamily
        font.weight: Root.Theme.fontWeight
        font.pixelSize: Root.Theme.fontSize
        font.bold: true
        text: root.active ? " SCREENCASTING" : ""
    }

    FileView {
        id: fv
        path: (Quickshell.env("TMPDIR") || "/tmp") + "/screencast.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const obj = JSON.parse(text());
                root.active = obj.state === "on";
                root.apps = (obj.apps || []).join(", ");
            } catch (e) {
                root.active = false;
            }
        }
        onLoadFailed: root.active = false
    }
}
