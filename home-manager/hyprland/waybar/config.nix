let
  glyph = str: builtins.fromJSON "\"${str}\"";
in
[
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
      "custom/clipboard"
      "idle_inhibitor"
      "pulseaudio#source"
      "custom/media"
      "pulseaudio#sink"
      "load"
      "battery"
    ];
    "wlr/workspaces" = {
      "format" = "{icon}";
      "on-click" = "activate";
      "all-outputs" = false;
      "sort-by-number" = true;
      "on-scroll-up" = "hyprctl dispatch workspace e+1";
      "on-scroll-down" = "hyprctl dispatch workspace e-1";
      "persistent_workspaces" = {
        "1" = [ ];
        "2" = [ ];
        "3" = [ ];
      };
    };
    "hyprland/workspaces" = {
      "all-outputs" = false;
      "format-icons" = {
        "active" = glyph "\\uf06a";
        "default" = glyph "\\uf111";
        "persistent" = "(P)";
      };
      "show-special" = false;
    };
    "sway/workspaces" = {
      "all-outputs" = false;
      "disable-scroll" = false;
      "format" = "{icon}{value}";
      "format-icons" = {
        "urgent" = "${glyph "\\uf06a"} ";
        "focused" = "";
        "default" = "";
      };
    };
    "sway/mode" = {
      "format" = "${glyph "\\uf6a5"} {}";
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
      "format" = "${glyph "\\ud83d\\udc49"} {}";
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
      "on-click" = "~/.config/waybar/custom_modules/clipboard.sh";
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
      "format" = "{}${glyph "\\u00b0"}C";
      "tooltip" = true;
      "interval" = 3600;
      "exec" = "wttrbar --location 'Frankfurt am Main, Germany'";
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
      "format-bluetooth" = "<span foreground=\"#55ACEE\">${glyph "\\udb80\\udcb0"}</span> {volume}%";
      "format-muted" = "<span foreground=\"#e27978\" font-weight=\"bold\">${glyph "\\udb81\\udf5f"} MUTE</span>";
      "format-icons" = {
        "headphones" = glyph "\\uf025";
        "handsfree" = glyph "\\uf590";
        "headset" = glyph "\\uf590";
        "phone" = glyph "\\uf095";
        "portable" = glyph "\\uf095";
        "car" = glyph "\\uf1b9";
        "default" = [
          (glyph "\\uf026")
          (glyph "\\uf027")
          (glyph "\\udb81\\udd7e")
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
        (glyph "\\u2581")
        (glyph "\\u2582")
        (glyph "\\u2583")
        (glyph "\\u2584")
        (glyph "\\u2585")
        (glyph "\\u2586")
        (glyph "\\u2587")
        (glyph "\\u2588")
      ];
      "actions" = {
        "on-click-right" = "mode";
      };
    };
    "pulseaudio#source" = {
      "scroll-step" = 5;
      "format" = "{format_source}";
      "format-source" = glyph "\\udb80\\udf6c";
      "format-source-muted" = "<span foreground=\"#e27978\" font-weight=\"bold\">${glyph "\\uf131"} MUTED</span>";
      "on-click" = "sh -c '~/bin/obs.zsh toggle-mute; ~/.config/sway/bin/barify source mute'";
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
      "format" = "<span color=\"#FFAB00\">${glyph "\\udb80\\udc85"}</span> {capacity}%";
      "format-full-full" = "<span color=\"green\">${glyph "\\udb80\\udc8b"}</span>";
      "format-discharging-critical" = "<span color=\"red\">!! {icon} {capacity}%</span>";
      "format-discharging" = "{icon} {capacity}%";
      "format-icons" = [
        (glyph "\\udb80\\udc7a")
        (glyph "\\udb80\\udc7c")
        (glyph "\\udb80\\udc7e")
        (glyph "\\udb80\\udc81")
        (glyph "\\udb80\\udc79")
      ];
      "tooltip" = true;
    };
    "bluetooth" = {
      "format" = "${glyph "\\uf294"} {status}";
      "format-disabled" = glyph "\\uf5b1";
      "format-connected" = "<span foreground=\"#55ACEE\">${glyph "\\udb80\\udcb3"}{num_connections}</span>";
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
        "activated" = "${glyph "\\uf0f4"} NO IDLE";
        "deactivated" = "${glyph "\\udb83\\udfaa"} IDLE";
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
        "spotify" = glyph "\\uf1bc";
        "plasma-browser-integration" = glyph "\\udb80\\ude39";
        "default" = glyph "\\ud83c\\udf9c";
      };
      "escape" = true;
      "exec" = "~/.config/waybar/custom_modules/mediaplayer-wrapper.sh 2> /dev/null";
      "on-click" = "playerctl play-pause --all-players";
    };
    "temperature" = {
      "critical-threshold" = 80;
      "thermal-zone" = 4;
      "interval" = 5;
      "format" = " {temperatureC}${glyph "\\u00b0"}C";
      "format-icons" = [
        (glyph "\\uf2cb")
        (glyph "\\uf2ca")
        (glyph "\\uf2c9")
        (glyph "\\uf2c8")
        (glyph "\\uf2c8")
      ];
      "tooltip" = true;
    };
    "cpu" = {
      "interval" = 5;
      "format" = "${glyph "\\uf2db"} {load} {avg_frequency}GHz";
      "states" = {
        "warning" = 70;
        "critical" = 90;
      };
    };
    "load" = {
      "interval" = 2;
      "format" = "{load1}";
    };
    "memory" = {
      "interval" = 5;
      "format" = "${glyph "\\udb80\\udf5b"} {}%";
      "states" = {
        "warning" = 70;
        "critical" = 90;
      };
    };
    "network" = {
      "interval" = 5;
      "format-wifi" = "${glyph "\\uf1eb"}  {essid} ({signalStrength}%)";
      "format-ethernet" = "${glyph "\\uf796"}  {ifname}: {ipaddr}/{cidr}";
      "format-disconnected" = "${glyph "\\u26a0"}  Disconnected";
      "tooltip-format" = "{ifname}: {ipaddr}";
    };
    "custom/keyboard-layout" = {
      "exec" = "swaymsg -t get_inputs | grep -m1 'xkb_active_layout_name' | cut -d '\"' -f4";
      "interval" = 30;
      "format" = "${glyph "\\uf11c"}  {}";
      "signal" = 1;
      "tooltip" = false;
    };
  }
]
