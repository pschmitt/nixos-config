import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    pluginId: "haAiUsage"

    StringSetting {
        settingKey: "server_file"
        label: "Home Assistant server file"
        description: "Path to a file containing the Home Assistant base URL (e.g. http://homeassistant.local:8123)"
        placeholder: "~/.config/ha-ai-usage/server"
        defaultValue: ""
    }

    StringSetting {
        settingKey: "token_file"
        label: "Home Assistant token file"
        description: "Path to a file containing a Home Assistant long-lived access token"
        placeholder: "~/.config/ha-ai-usage/token"
        defaultValue: ""
    }

    SliderSetting {
        settingKey: "refresh_interval"
        label: "Refresh interval"
        description: "How often to poll Home Assistant for updated quotas"
        defaultValue: 60
        minimum: 10
        maximum: 600
        unit: "s"
    }

    StringSetting {
        settingKey: "card_filter"
        label: "Card filter"
        description: "Comma-separated terms to filter/order shown provider cards (empty shows all)"
        placeholder: ""
        defaultValue: ""
    }
}
