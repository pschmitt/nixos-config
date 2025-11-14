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
  inherit (pkgs.stdenv.hostPlatform) system;

  hyprdynamicmonitorsPkg = inputs.hyprdynamicmonitors.packages.${system}.default;
  callbackScriptPath = "${config.home.homeDirectory}/.config/hyprdynamicmonitors/profile-callback.sh";
  callbackScriptEscaped = escapeShellArg callbackScriptPath;

  callbackScript = pkgs.writeShellScript "hyprdynamicmonitors-profile-callback.sh" ''
    set -euo pipefail

    STATE_BASE="''${XDG_CACHE_HOME:-''${HOME}/.cache}"
    STATEFILE="$STATE_BASE/hyprdynamicmonitors/current-state.json"
    LEGACY_STATEFILE="$STATE_BASE/shikane/current-state.json"
    JQ_BIN=${pkgs.jq}/bin/jq

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
      write-state "$LEGACY_STATEFILE" "$state"
    }

    get-state() {
      local source="$STATEFILE"
      if [[ ! -s "$source" && -s "$LEGACY_STATEFILE" ]]
      then
        source="$LEGACY_STATEFILE"
      fi
      "$JQ_BIN" -er '.state' "$source"
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
          hyprctl reload
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

  hostName = if osConfig == null then null else (osConfig.networking.hostName or null);
  isGk4 = hostName == "gk4";

  laptopMonitorAutoSettings =
    if isGk4 then "preferred,auto,1.666,transform,3" else "preferred,auto,1";
  laptopMonitorOriginSettings =
    if isGk4 then "preferred,0x0,1.666,transform,3" else "preferred,0x0,1";

  laptopTemplate = tmpl "laptop.go.tmpl" ''
    {{- $laptop := index .MonitorsByTag "laptop" -}}
    monitor={{$laptop.Name}},${laptopMonitorAutoSettings}
    {{- range .ExtraMonitors }}
    monitor={{.Name}},disable
    {{- end }}
  '';

  laptopEdpM14Template = tmpl "laptop-edp-m14.go.tmpl" ''
    {{- $laptop := index .MonitorsByTag "laptop" -}}
    {{- $lenovo := index .MonitorsByTag "lenovo_m14" -}}
    monitor={{$laptop.Name}},${laptopMonitorOriginSettings}
    monitor={{$lenovo.Name}},preferred,1920x0,1
    {{- range .ExtraMonitors }}
    monitor={{.Name}},disable
    {{- end }}
  '';

  dualDisplayTemplate = tmpl "docked-dual.go.tmpl" ''
    {{- $lenovo := index .MonitorsByTag "lenovo_m14" -}}
    {{- $lg := index .MonitorsByTag "lg_wqhd" -}}
    monitor={{$lg.Name}},3440x1440@60,0x0,1
    monitor={{$lenovo.Name}},1920x1080@60,-1920x0,1
    {{- range .ExtraMonitors }}
    monitor={{.Name}},disable
    {{- end }}
  '';

  dualDisplayNoInternalTemplate = tmpl "dual-display-no-internal.go.tmpl" ''
    {{- $lenovo := index .MonitorsByTag "lenovo_m14" -}}
    {{- $lg := index .MonitorsByTag "lg_wqhd" -}}
    {{- $laptop := index .MonitorsByTag "laptop" -}}
    monitor={{$lg.Name}},3440x1440@60,0x0,1
    monitor={{$lenovo.Name}},1920x1080@60,-1920x0,1
    monitor={{$laptop.Name}},disable
    {{- range .ExtraMonitors }}
    monitor={{.Name}},disable
    {{- end }}
  '';

  dualDisplayPiKvmTemplate = tmpl "dual-display-pikvm.go.tmpl" ''
    {{- $lenovo := index .MonitorsByTag "lenovo_m14" -}}
    {{- $lg := index .MonitorsByTag "lg_wqhd" -}}
    {{- $pikvm := index .MonitorsByTag "pikvm" -}}
    monitor={{$lg.Name}},3440x1440@60,0x0,1
    monitor={{$lenovo.Name}},1920x1080@60,-1920x0,1
    monitor={{$pikvm.Name}},disable
    {{- range .ExtraMonitors }}
    monitor={{.Name}},disable
    {{- end }}
  '';

  dualDisplayPiKvmLaptopTemplate = tmpl "dual-display-pikvm-with-laptop.go.tmpl" ''
    {{- $lenovo := index .MonitorsByTag "lenovo_m14" -}}
    {{- $lg := index .MonitorsByTag "lg_wqhd" -}}
    {{- $pikvm := index .MonitorsByTag "pikvm" -}}
    {{- $laptop := index .MonitorsByTag "laptop" -}}
    monitor={{$lg.Name}},3440x1440@60,0x0,1
    monitor={{$lenovo.Name}},1920x1080@60,-1920x0,1
    monitor={{$pikvm.Name}},disable
    monitor={{$laptop.Name}},disable
    {{- range .ExtraMonitors }}
    monitor={{.Name}},disable
    {{- end }}
  '';

  fallbackConfig = tmpl "hyprdynamicmonitors-fallback.conf" ''
    monitor=,preferred,auto,1
  '';

  callbackCommand = profile: "${callbackScriptEscaped} set ${escapeShellArg profile}";

  regexMonitor =
    { pattern, tag }:
    {
      description = pattern;
      monitor_tag = tag;
      match_description_using_regex = true;
    };
in
{
  imports = [ inputs.hyprdynamicmonitors.homeManagerModules.hyprdynamicmonitors ];

  home =
    let
      profilesCommon = {
        "laptop" = {
          config_file = "hyprconfigs/laptop.go.tmpl";
          config_file_type = "template";
          post_apply_exec = callbackCommand "laptop";
          conditions.required_monitors = [
            {
              name = "eDP-1";
              monitor_tag = "laptop";
            }
          ];
        };
        "laptop-edp-m14" = {
          config_file = "hyprconfigs/laptop-edp-m14.go.tmpl";
          config_file_type = "template";
          post_apply_exec = callbackCommand "laptop-edp-m14";
          conditions.required_monitors = [
            {
              name = "eDP-1";
              monitor_tag = "laptop";
            }
            (regexMonitor {
              pattern = "Lenovo.* M14.*";
              tag = "lenovo_m14";
            })
          ];
        };

        "dual-display" = {
          config_file = "hyprconfigs/docked-dual.go.tmpl";
          config_file_type = "template";
          post_apply_exec = callbackCommand "dual-display";
          conditions.required_monitors = [
            (regexMonitor {
              pattern = "Lenovo.* M14.*";
              tag = "lenovo_m14";
            })
            (regexMonitor {
              pattern = "LG Electronics .* WQHD .*";
              tag = "lg_wqhd";
            })
          ];
        };

        "dual-display-pikvm" = {
          config_file = "hyprconfigs/dual-display-pikvm.go.tmpl";
          config_file_type = "template";
          post_apply_exec = callbackCommand "dual-display-pikvm";
          conditions.required_monitors = [
            (regexMonitor {
              pattern = "Lenovo.* M14.*";
              tag = "lenovo_m14";
            })
            (regexMonitor {
              pattern = "LG Electronics .* WQHD .*";
              tag = "lg_wqhd";
            })
            (regexMonitor {
              pattern = ".*(PiKVM|Synaptics Inc).*";
              tag = "pikvm";
            })
          ];
        };

        "dual-display-pikvm-with-internal" = {
          config_file = "hyprconfigs/dual-display-pikvm-with-laptop.go.tmpl";
          config_file_type = "template";
          post_apply_exec = callbackCommand "dual-display-pikvm-with-internal";
          conditions.required_monitors = [
            (regexMonitor {
              pattern = "Lenovo.* M14.*";
              tag = "lenovo_m14";
            })
            (regexMonitor {
              pattern = "LG Electronics .* WQHD .*";
              tag = "lg_wqhd";
            })
            (regexMonitor {
              pattern = ".*(PiKVM|Synaptics Inc).*";
              tag = "pikvm";
            })
            {
              name = "eDP-1";
              monitor_tag = "laptop";
            }
          ];
        };

        "dual-display-no-internal" = {
          config_file = "hyprconfigs/dual-display-no-internal.go.tmpl";
          config_file_type = "template";
          post_apply_exec = callbackCommand "dual-display-no-internal";
          conditions.required_monitors = [
            (regexMonitor {
              pattern = "Lenovo.* M14.*";
              tag = "lenovo_m14";
            })
            (regexMonitor {
              pattern = "LG Electronics .* WQHD .*";
              tag = "lg_wqhd";
            })
            {
              name = "eDP-1";
              monitor_tag = "laptop";
            }
          ];
        };
      };

      profiles = profilesCommon;

      extraFilesCommon = {
        "hyprdynamicmonitors/hyprconfigs/laptop.go.tmpl" = laptopTemplate;
        "hyprdynamicmonitors/hyprconfigs/laptop-edp-m14.go.tmpl" = laptopEdpM14Template;
        "hyprdynamicmonitors/hyprconfigs/docked-dual.go.tmpl" = dualDisplayTemplate;
        "hyprdynamicmonitors/hyprconfigs/dual-display-pikvm.go.tmpl" = dualDisplayPiKvmTemplate;
        "hyprdynamicmonitors/hyprconfigs/dual-display-pikvm-with-laptop.go.tmpl" =
          dualDisplayPiKvmLaptopTemplate;
        "hyprdynamicmonitors/hyprconfigs/dual-display-no-internal.go.tmpl" = dualDisplayNoInternalTemplate;
        "hyprdynamicmonitors/hyprconfigs/default.conf" = fallbackConfig;
      };

      extraFiles = extraFilesCommon;
    in
    {
      file."${callbackScriptPath}" = {
        source = callbackScript;
        executable = true;
      };

      packages = [ hyprdynamicmonitorsPkg ];

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

  wayland.windowManager.hyprland.settings.source = lib.mkAfter [
    # Include HyprDynamicMonitors output so Hyprland uses the generated layout.
    "$config_dir/monitors.conf"
  ];
}
