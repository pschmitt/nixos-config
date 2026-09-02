//@ pragma UseQApplication
import QtQuick
import Quickshell

Scope {
    Variants {
        model: Quickshell.screens
        delegate: BarSpacer {}
    }
    Variants {
        model: Quickshell.screens
        delegate: Bar {}
    }
}
