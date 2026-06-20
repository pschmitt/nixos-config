{
  enableSoftKeyboard ? false,
}:
[
  (
    {
      "layer" = "top";
      "position" = "top";
      "height" = 30;
      "modules-left" = [
        "hyprland/workspaces"
        "sway/workspaces"
        "sway/mode"
        "hyprland/submap"
        "wlr/taskbar"
      ];
      "modules-center" = [
        "custom/weather"
        "clock"
        "custom/timewarrior"
      ];
      "modules-right" = [
        "custom/screencast"
        "tray"
        "idle_inhibitor"
      ]
      ++ (if enableSoftKeyboard then [ "custom/soft-keyboard" ] else [ ])
      ++ [
        "pulseaudio#source"
        "custom/media"
        "pulseaudio#sink"
        "load"
        "power-profiles-daemon"
        "battery"
      ];
      "wlr/workspaces" = {
        "format" = "{icon}";
        "on-click" = "activate";
        "all-outputs" = false;
        "sort-by-number" = true;
        "on-scroll-up" = "hyprctl dispatch 'hl.dsp.focus({ workspace = \"e+1\" })'";
        "on-scroll-down" = "hyprctl dispatch 'hl.dsp.focus({ workspace = \"e-1\" })'";
        "persistent_workspaces" = {
          "1" = [ ];
          "2" = [ ];
          "3" = [ ];
        };
      };
      "hyprland/workspaces" = {
        "all-outputs" = false;
        "format-icons" = {
          "active" = "";
          "default" = "";
          "persistent" = "(P)";
        };
        "show-special" = false;
      };
      "sway/workspaces" = {
        "all-outputs" = false;
        "disable-scroll" = false;
        "format" = "{icon}{value}";
        "format-icons" = {
          "urgent" = " ";
          "focused" = "";
          "default" = "";
        };
      };
      "sway/mode" = {
        "format" = " {}";
        "max-length" = 50;
      };
      "wlr/taskbar" = {
        "format" = "{icon}";
        "icon-size" = 20;
        "icon-theme" = "Papirus-Dark";
        "tooltip-format" = "{title}";
        "on-click" = "activate";
        "on-click-middle" = "close";
        "ignore-list" = [
          "kitty-scratch"
          "kitty-scratchpad"
          "org.gnome.Nautilus"
          "pavucontrol"
          "scratchterm"
          "term_scratchpad"
          "wezterm-scratchpad"
        ];
        "app_ids-mapping" = {
          "firefoxdeveloperedition" = "firefox-developer-edition";
        };
        "all-outputs" = false;
        "rewrite" = {
          "Firefox Web Browser" = "Firefox";
          "Foot Server" = "Foot";
          "Foot Client" = "Foot";
        };
      };
      "sway/window" = {
        "format" = "{}";
        "max-length" = 120;
      };
      "hyprland/window" = {
        "format" = "👉 {}";
        "separate-outputs" = true;
      };
      "hyprland/submap" = {
        "format" = "{}";
        "max-length" = 20;
        "tooltip" = false;
      };
      "custom/clipboard" = {
        "exec" = "~/.config/waybar/custom_modules/clipboard.sh format";
        "interval" = "once";
        "return-type" = "json";
        "on-click" = "walker -m clipboard";
        "spacing" = 5;
      };
      "custom/timewarrior" = {
        "exec" = "~/.config/waybar/custom_modules/timewarrior.sh format";
        "interval" = 5;
        "return-type" = "json";
        "spacing" = 5;
        "signal" = 7;
      };
      "custom/screencast" = {
        "exec" = "~/.config/waybar/custom_modules/screencast.sh format";
        "interval" = 5;
        "return-type" = "json";
        "spacing" = 5;
        "signal" = 7;
      };
      "custom/modkey" = {
        "format" = "{}";
        "exec" = "sudo ~/.config/waybar/custom_modules/mod-key.py 2>/dev/null";
        "restart-interval" = 5;
        "return-type" = "json";
        "escape" = true;
      };
      "custom/weather" = {
        "format" = "{}°C";
        "tooltip" = true;
        "interval" = 3600;
        "exec" = "wttrbar --location 'Berlin, Germany'";
        "return-type" = "json";
      };
      "tray" = {
        "icon-size" = 18;
        "spacing" = 5;
      };
      "pulseaudio#sink" = {
        "scroll-step," = 5;
        "ignored-sinks" = [
          "Easy Effects Sink"
        ];
        "format" = "{icon} {volume}%";
        "format-bluetooth" = "<span foreground=\"#55ACEE\">󰂰</span> {volume}%";
        "format-muted" = "<span foreground=\"#e27978\" font-weight=\"bold\">󰝟 MUTE</span>";
        "format-icons" = {
          "headphones" = "";
          "handsfree" = "";
          "headset" = "";
          "phone" = "";
          "portable" = "";
          "car" = "";
          "default" = [
            ""
            ""
            "󰕾"
          ];
        };
        "on-click" = "~/.config/sway/bin/barify sink mute";
        "on-click-right" = "~/.config/sway/bin/scratchpad.sh pavucontrol";
        "on-scroll-down" = "~/.config/sway/bin/barify sink down";
        "on-scroll-up" = "~/.config/sway/bin/barify sink up";
      };
      "cava" = {
        "framerate" = 30;
        "autosens" = 1;
        "bars" = 4;
        "hide_on_silence" = true;
        "lower_cutoff_freq" = 50;
        "higher_cutoff_freq" = 10000;
        "cava_config" = "/home/pschmitt/.config/waybar/cava.config";
        "stereo" = true;
        "reverse" = false;
        "bar_delimiter" = 0;
        "monstercat" = true;
        "waves" = false;
        "noise_reduction" = 0.2;
        "input_delay" = 2;
        "format-icons" = [
          "▁"
          "▂"
          "▃"
          "▄"
          "▅"
          "▆"
          "▇"
          "█"
        ];
        "actions" = {
          "on-click-right" = "mode";
        };
      };
      "pulseaudio#source" = {
        "scroll-step" = 5;
        "format" = "{format_source}";
        "format-source" = "󰍬";
        "format-source-muted" = "<span foreground=\"#e27978\" font-weight=\"bold\"> MUTED</span>";
        "on-click" = "sh -c 'obs-control toggle-mute; ~/.config/sway/bin/barify source mute'";
        "on-click-right" = "sh -c 'swaymsg [app_id=\"pavucontrol\"] scratchpad show || exec pavucontrol'";
        "on-scroll-down" = "~/.config/sway/bin/barify source down";
        "on-scroll-up" = "~/.config/sway/bin/barify source up";
      };
      "battery" = {
        "interval" = 5;
        "states" = {
          "full" = 80;
          "warning" = 30;
          "critical" = 15;
        };
        "format" = "<span color=\"#FFAB00\">󰂅</span> {capacity}%";
        "format-full-full" = "<span color=\"green\">󰂋</span>";
        "format-discharging-critical" = "<span color=\"red\">!! {icon} {capacity}%</span>";
        "format-discharging" = "{icon} {capacity}%";
        "format-icons" = [
          "󰁺"
          "󰁼"
          "󰁾"
          "󰂁"
          "󰁹"
        ];
        "tooltip" = true;
      };
      "bluetooth" = {
        "format" = " {status}";
        "format-disabled" = "";
        "format-connected" = "<span foreground=\"#55ACEE\">󰂳{num_connections}</span>";
        "tooltip-format" = "{controller_alias}\t{controller_address}";
        "tooltip-format-connected" = "{controller_alias}\t{controller_address}\n\n{device_enumerate}";
        "tooltip-format-enumerate-connected" = "{device_alias}\t{device_address}";
        "tooltip-format-enumerate-connected-battery" =
          "{device_alias}\t{device_address}\t{device_battery_percentage}%";
        "on-click" = "blueman-manager";
      };
      "idle_inhibitor" = {
        "format" = "{icon}";
        "format-icons" = {
          "activated" = " NO IDLE";
          "deactivated" = "󰾪 IDLE";
        };
      };
      "clock" = {
        "interval" = 1;
        "format" = "{:%H:%M:%S}";
        "locale" = "de_DE.UTF-8";
        "tooltip-format" = "{:%A %d.%m.%Y (Week: %V)}";
        "on-click" = "~/.config/sway/bin/scratchpad.sh calendar";
      };
      "custom/media" = {
        "format" = "{}";
        "return-type" = "json";
        "max-length" = 40;
        "format-icons" = {
          "spotify" = "";
          "plasma-browser-integration" = "󰈹";
          "default" = "🎜";
        };
        "escape" = true;
        "exec" = "~/.config/waybar/custom_modules/mediaplayer-wrapper.sh 2> /dev/null";
        "on-click" = "playerctl play-pause --all-players";
      };
      "temperature" = {
        "critical-threshold" = 80;
        "thermal-zone" = 4;
        "interval" = 5;
        "format" = " {temperatureC}°C";
        "format-icons" = [
          ""
          ""
          ""
          ""
          ""
        ];
        "tooltip" = true;
      };
      "cpu" = {
        "interval" = 5;
        "format" = " {load} {avg_frequency}GHz";
        "states" = {
          "warning" = 70;
          "critical" = 90;
        };
      };
      "load" = {
        "interval" = 2;
        "format" = "{load1}";
      };
      "power-profiles-daemon" = {
        "format" = "{icon}";
        "tooltip-format" = "Power profile: {profile}\nDriver: {driver}";
        "format-icons" = {
          "default" = "";
          "performance" = "";
          "balanced" = "";
          "power-saver" = "";
        };
      };
      "memory" = {
        "interval" = 5;
        "format" = "󰍛 {}%";
        "states" = {
          "warning" = 70;
          "critical" = 90;
        };
      };
      "network" = {
        "interval" = 5;
        "format-wifi" = "  {essid} ({signalStrength}%)";
        "format-ethernet" = "  {ifname}: {ipaddr}/{cidr}";
        "format-disconnected" = "⚠  Disconnected";
        "tooltip-format" = "{ifname}: {ipaddr}";
      };
      "custom/keyboard-layout" = {
        "exec" = "swaymsg -t get_inputs | grep -m1 'xkb_active_layout_name' | cut -d '\"' -f4";
        "interval" = 30;
        "format" = "  {}";
        "signal" = 1;
        "tooltip" = false;
      };
    }
    // (
      if enableSoftKeyboard then
        {
          "custom/soft-keyboard" = {
            "exec" = "~/.config/waybar/custom_modules/soft-keyboard.sh format";
            "interval" = 5;
            "return-type" = "json";
            "signal" = 8;
            "on-click" = "sh -c '~/.config/hypr/bin/toggle-soft-keyboard.sh && pkill -RTMIN+8 waybar'";
          };
        }
      else
        { }
    )
  )
]
