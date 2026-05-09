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

  # Lua table fields for laptop monitor modes (injected into hl.monitor({...}) calls)
  laptopMonitorAuto =
    if isGk4 then
      "mode = \"preferred\", position = \"auto\",       scale = 1.666, transform = 3"
    else
      "mode = \"preferred\", position = \"auto\",       scale = 1";
  laptopMonitorOrigin =
    if isGk4 then
      "mode = \"preferred\", position = \"0x0\",        scale = 1.666, transform = 3"
    else
      "mode = \"preferred\", position = \"0x0\",        scale = 1";
  laptopMonitorExternal =
    if isGk4 then
      "mode = \"preferred\", position = \"auto-right\", scale = 1.666, transform = 3"
    else
      "mode = \"preferred\", position = \"auto-right\", scale = 1";

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

  # Helper to create Lua templates; appends disable rules for extra monitors.
  mkTmpl =
    name: content:
    tmpl "${name}.go.tmpl" ''
      ${content}
      {{- range .ExtraMonitors }}
      hl.monitor({ output = "{{.Name}}", mode = "disabled" })
      {{- end }}
    '';

  fallbackConfig = tmpl "hyprdynamicmonitors-fallback.lua" ''
    hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
  '';

  # Profile configurations: name -> { tags, content }
  profileConfigs = {
    "laptop" = {
      tags = [ "laptop" ];
      content = ''
        {{- $laptop := index .MonitorsByTag "laptop" -}}
        hl.monitor({ output = "{{$laptop.Name}}", ${laptopMonitorAuto} })
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
        hl.monitor({ output = "{{$laptop.Name}}", ${laptopMonitorOrigin} })
        hl.monitor({ output = "{{$lenovo.Name}}", mode = "preferred", position = "auto-right", scale = 1 })
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
        hl.monitor({ output = "{{$laptop.Name}}", ${laptopMonitorOrigin} })
        hl.monitor({ output = "{{$lg.Name}}", mode = "3440x1440@60", position = "auto-right", scale = 1 })
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
        hl.monitor({ output = "{{$lg.Name}}",     mode = "3440x1440@60",  position = "0x0",    scale = 1 })
        hl.monitor({ output = "{{$lenovo.Name}}", mode = "1920x1080@60",  position = "-1920x0", scale = 1 })
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
        hl.monitor({ output = "{{$lg.Name}}",     mode = "3440x1440@60",  position = "0x0",    scale = 1 })
        hl.monitor({ output = "{{$lenovo.Name}}", mode = "1920x1080@60",  position = "-1920x0", scale = 1 })
        hl.monitor({ output = "{{$pikvm.Name}}", mode = "disabled" })
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
        hl.monitor({ output = "{{$lg.Name}}",     mode = "3440x1440@60",  position = "0x0",    scale = 1 })
        hl.monitor({ output = "{{$lenovo.Name}}", mode = "1920x1080@60",  position = "-1920x0", scale = 1 })
        hl.monitor({ output = "{{$pikvm.Name}}",  mode = "disabled" })
        hl.monitor({ output = "{{$laptop.Name}}", mode = "disabled" })
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
        hl.monitor({ output = "{{$lg.Name}}",     mode = "3440x1440@60",  position = "0x0",    scale = 1 })
        hl.monitor({ output = "{{$lenovo.Name}}", mode = "1920x1080@60",  position = "-1920x0", scale = 1 })
        hl.monitor({ output = "{{$laptop.Name}}", mode = "disabled" })
      '';
    };
    "triple-display-stacked" = {
      tags = [
        "laptop"
        "lenovo_m14"
        "lg_wqhd"
      ];
      content = ''
        {{- $laptop := index .MonitorsByTag "laptop" -}}
        {{- $lenovo := index .MonitorsByTag "lenovo_m14" -}}
        {{- $lg := index .MonitorsByTag "lg_wqhd" -}}
        hl.monitor({ output = "{{$laptop.Name}}", mode = "1920x1200@48",  position = "0x240",   scale = 1 })
        hl.monitor({ output = "{{$lg.Name}}",     mode = "3440x1440@59",  position = "1920x0",  scale = 1 })
        hl.monitor({ output = "{{$lenovo.Name}}", mode = "1920x1080@60",  position = "986x1440", scale = 1 })
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
      "hyprdynamicmonitors/hyprconfigs/default.lua" = fallbackConfig;
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
      pkgs.kanshi
      pkgs.shikane
    ];

    hyprdynamicmonitors = {
      enable = true;
      package = hyprdynamicmonitorsPkg;
      configFile = (pkgs.formats.toml { }).generate "hyprdynamicmonitors-config.toml" {
        # Output Lua so hyprland.lua can pcall(require, "monitors").
        general.destination = "${config.xdg.configHome}/hypr/monitors.lua";
        inherit profiles;
        fallback_profile = {
          config_file = "hyprconfigs/default.lua";
          config_file_type = "static";
          post_apply_exec = callbackCommand "default";
        };
      };

      inherit extraFiles;
    };
  };
}
