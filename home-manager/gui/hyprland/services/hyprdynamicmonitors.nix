{
  config,
  inputs,
  lib,
  osConfig ? null,
  pkgs,
  ...
}:

let
  inherit (lib) escapeShellArg;

  hyprdynamicmonitorsPkg =
    inputs.hyprdynamicmonitors.packages.${pkgs.stdenv.hostPlatform.system}.default;
  callbackScriptPath = "${config.home.homeDirectory}/.config/hyprdynamicmonitors/profile-callback.sh";
  callbackScriptEscaped = escapeShellArg callbackScriptPath;
  hyprConfigAutoreloadDisabled =
    config.wayland.windowManager.hyprland.settings.misc.disable_autoreload or false;

  callbackScript = pkgs.writeShellScript "hyprdynamicmonitors-profile-callback.sh" ''
    set -euo pipefail

    STATE_BASE="''${XDG_CACHE_HOME:-''${HOME}/.cache}"
    STATEFILE="$STATE_BASE/hyprdynamicmonitors/current-state.json"
    JQ_BIN=${pkgs.jq}/bin/jq
    MANUAL_RELOAD_REQUIRED="${if hyprConfigAutoreloadDisabled then "1" else ""}"

    usage() {
      echo "Usage: $0 save|get [STATE]"
    }

    write-state() {
      local target="$1"
      mkdir -p "$(dirname "$target")"
      rm -f "$target"
      "$JQ_BIN" -n \
        --arg d "$(date -Iseconds)" \
        --arg s "$2" \
        '{"date": $d, "state": $s}' \
        > "$target"
    }

    save-state() {
      local state="$1"
      write-state "$STATEFILE" "$state"
    }

    get-state() {
      "$JQ_BIN" -er '.state' "$STATEFILE"
    }

    if [[ "''${BASH_SOURCE[0]}" == "$0" ]]
    then
      if [[ $# -lt 1 ]]
      then
        usage >&2
        exit 2
      fi

      case "$1" in
        save|set|store)
          if [[ $# -lt 2 ]]
          then
            usage >&2
            exit 2
          fi
          save-state "$2"
          if [[ -n "$MANUAL_RELOAD_REQUIRED" ]]
          then
            hyprctl reload
          fi
          ;;
        get|retrieve)
          get-state
          ;;
        *)
          usage >&2
          exit 2
          ;;
      esac
    fi
  '';

  tmpl = name: text: pkgs.writeText name text;

  hostName = if osConfig != null then osConfig.networking.hostName or "" else "";
  isGk4 = hostName == "gk4";

  laptopMonitorAutoSettings =
    if isGk4 then "preferred,auto,1.666,transform,3" else "preferred,auto,1";
  laptopMonitorOriginSettings =
    if isGk4 then "preferred,0x0,1.666,transform,3" else "preferred,0x0,1";
  lenovoRightOfLaptopPosition = if isGk4 then "1600x0" else "1920x0";

  callbackCommand = profile: "${callbackScriptEscaped} set ${escapeShellArg profile}";

  regexMonitor =
    { pattern, tag }:
    {
      description = pattern;
      monitor_tag = tag;
      match_description_using_regex = true;
    };

  monitorTags = {
    laptop = {
      name = "eDP-1";
      monitor_tag = "laptop";
    };
    lenovo_m14 = regexMonitor {
      pattern = "Lenovo.* M14.*";
      tag = "lenovo_m14";
    };
    lg_wqhd = regexMonitor {
      pattern = "LG Electronics .* WQHD .*";
      tag = "lg_wqhd";
    };
    pikvm = regexMonitor {
      pattern = ".*(PiKVM|Synaptics Inc).*";
      tag = "pikvm";
    };
  };

  # Helper to create templates with common suffix to disable extra monitors
  mkTmpl =
    name: content:
    tmpl "${name}.go.tmpl" ''
      ${content}
      {{- range .ExtraMonitors }}
      monitor={{.Name}},disable
      {{- end }}
    '';

  fallbackConfig = tmpl "hyprdynamicmonitors-fallback.conf" ''
    monitor=,preferred,auto,1
  '';

  # Profile configurations: name -> { tags, content }
  profileConfigs = {
    "laptop" = {
      tags = [ "laptop" ];
      content = ''
        {{- $laptop := index .MonitorsByTag "laptop" -}}
        monitor={{$laptop.Name}},${laptopMonitorAutoSettings}
      '';
    };
    "laptop-edp-m14" = {
      tags = [
        "laptop"
        "lenovo_m14"
      ];
      content = ''
        {{- $laptop := index .MonitorsByTag "laptop" -}}
        {{- $lenovo := index .MonitorsByTag "lenovo_m14" -}}
        monitor={{$laptop.Name}},${laptopMonitorOriginSettings}
        monitor={{$lenovo.Name}},preferred,${lenovoRightOfLaptopPosition},1
      '';
    };
    "laptop-lg-wqhd" = {
      tags = [
        "laptop"
        "lg_wqhd"
      ];
      content = ''
        {{- $laptop := index .MonitorsByTag "laptop" -}}
        {{- $lg := index .MonitorsByTag "lg_wqhd" -}}
        monitor={{$lg.Name}},3440x1440@60,0x0,1
        monitor={{$laptop.Name}},${laptopMonitorAutoSettings}
      '';
    };
    "dual-display" = {
      tags = [
        "lenovo_m14"
        "lg_wqhd"
      ];
      content = ''
        {{- $lenovo := index .MonitorsByTag "lenovo_m14" -}}
        {{- $lg := index .MonitorsByTag "lg_wqhd" -}}
        monitor={{$lg.Name}},3440x1440@60,0x0,1
        monitor={{$lenovo.Name}},1920x1080@60,-1920x0,1
      '';
    };
    "dual-display-pikvm" = {
      tags = [
        "lenovo_m14"
        "lg_wqhd"
        "pikvm"
      ];
      content = ''
        {{- $lenovo := index .MonitorsByTag "lenovo_m14" -}}
        {{- $lg := index .MonitorsByTag "lg_wqhd" -}}
        {{- $pikvm := index .MonitorsByTag "pikvm" -}}
        monitor={{$lg.Name}},3440x1440@60,0x0,1
        monitor={{$lenovo.Name}},1920x1080@60,-1920x0,1
        monitor={{$pikvm.Name}},disable
      '';
    };
    "dual-display-pikvm-with-internal" = {
      tags = [
        "lenovo_m14"
        "lg_wqhd"
        "pikvm"
        "laptop"
      ];
      content = ''
        {{- $lenovo := index .MonitorsByTag "lenovo_m14" -}}
        {{- $lg := index .MonitorsByTag "lg_wqhd" -}}
        {{- $pikvm := index .MonitorsByTag "pikvm" -}}
        {{- $laptop := index .MonitorsByTag "laptop" -}}
        monitor={{$lg.Name}},3440x1440@60,0x0,1
        monitor={{$lenovo.Name}},1920x1080@60,-1920x0,1
        monitor={{$pikvm.Name}},disable
        monitor={{$laptop.Name}},disable
      '';
    };
    "dual-display-no-internal" = {
      tags = [
        "lenovo_m14"
        "lg_wqhd"
        "laptop"
      ];
      content = ''
        {{- $lenovo := index .MonitorsByTag "lenovo_m14" -}}
        {{- $lg := index .MonitorsByTag "lg_wqhd" -}}
        {{- $laptop := index .MonitorsByTag "laptop" -}}
        monitor={{$lg.Name}},3440x1440@60,0x0,1
        monitor={{$lenovo.Name}},1920x1080@60,-1920x0,1
        monitor={{$laptop.Name}},disable
      '';
    };
  };

  profiles = lib.mapAttrs (name: cfg: {
    config_file = "hyprconfigs/${name}.go.tmpl";
    config_file_type = "template";
    post_apply_exec = callbackCommand name;
    conditions.required_monitors = map (tag: monitorTags.${tag}) cfg.tags;
  }) profileConfigs;

  extraFiles =
    (lib.mapAttrs' (
      name: cfg:
      lib.nameValuePair "hyprdynamicmonitors/hyprconfigs/${name}.go.tmpl" (mkTmpl name cfg.content)
    ) profileConfigs)
    // {
      "hyprdynamicmonitors/hyprconfigs/default.conf" = fallbackConfig;
    };
in
{
  imports = [ inputs.hyprdynamicmonitors.homeManagerModules.hyprdynamicmonitors ];

  home = {
    file."${callbackScriptPath}" = {
      source = callbackScript;
      executable = true;
    };

    packages = [
      hyprdynamicmonitorsPkg

      # Alternative monitor config tools
      pkgs.kanshi
      pkgs.shikane # kanshi alternative, rust
    ];

    hyprdynamicmonitors = {
      enable = true;
      package = hyprdynamicmonitorsPkg;
      configFile = (pkgs.formats.toml { }).generate "hyprdynamicmonitors-config.toml" {
        general.destination = "${config.xdg.configHome}/hypr/config.d/monitors.conf";
        inherit profiles;
        fallback_profile = {
          config_file = "hyprconfigs/default.conf";
          config_file_type = "static";
          post_apply_exec = callbackCommand "default";
        };
      };

      inherit extraFiles;
    };
  };

  wayland.windowManager.hyprland.settings.source = [
    # Include HyprDynamicMonitors output so Hyprland uses the generated layout.
    "$config_dir/monitors.conf"
  ];
}
