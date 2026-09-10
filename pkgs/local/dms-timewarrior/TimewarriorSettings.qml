import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    pluginId: "timewarrior"

    SliderSetting {
        settingKey: "overtime_hours"
        label: "Overtime threshold"
        description: "Bar duration/day total turns overtime-colored past this many hours"
        defaultValue: 7
        minimum: 1
        maximum: 24
        unit: "h"
    }

    SliderSetting {
        settingKey: "breakdown_days"
        label: "Breakdown window"
        description: "How many days back the panel's day breakdown reaches, ending today"
        defaultValue: 14
        minimum: 2
        maximum: 62
        unit: "d"
    }

    SliderSetting {
        settingKey: "poll_interval"
        label: "Poll interval"
        description: "How often the bar re-checks Timewarrior's tracking state"
        defaultValue: 5
        minimum: 2
        maximum: 60
        unit: "s"
    }
}
