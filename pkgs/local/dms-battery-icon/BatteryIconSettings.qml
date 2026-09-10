import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    pluginId: "batteryIcon"

    ToggleSetting {
        settingKey: "show_peripheral_low_badge"
        label: "Low peripheral badge"
        description: "Show a small red dot on the icon when a Bluetooth/UPower peripheral (mouse, keyboard, headset, ...) is low on battery"
        defaultValue: true
    }
}
