{
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  hostName = osConfig.networking.hostName or "";
  isGk4 = hostName == "gk4";
  # GPD Pocket 4 needs 1.666667 scale; other IIO-sensor devices default to 1.
  monitorScale = if isGk4 then "1.666667" else "1";

  # iio-hyprland uses `hyprctl keyword monitor NAME,transform,N` which is
  # broken in Lua config mode. This wrapper intercepts those calls and
  # converts them to `wlr-randr` (wlr-output-management protocol) instead.
  # Scale is passed via MONITOR_SCALE so transform and scale are applied
  # together; setting either alone resets the other via wlr_output_management.
  hyprctlWrapper = pkgs.writeShellScriptBin "hyprctl" ''
        usage() {
          cat >&2 <<EOF
        Usage: $(basename "$0") HYPRCTL_ARGS...
    EOF
        }

        transform_name() {
          case "$1" in
            0)
              printf 'normal\n'
              ;;
            1)
              printf '90\n'
              ;;
            2)
              printf '180\n'
              ;;
            3)
              printf '270\n'
              ;;
            4)
              printf 'flipped\n'
              ;;
            5)
              printf 'flipped-90\n'
              ;;
            6)
              printf 'flipped-180\n'
              ;;
            7)
              printf 'flipped-270\n'
              ;;
            *)
              printf 'normal\n'
              ;;
          esac
        }

        apply_transform() {
          local batch="$1"
          local monitor
          local scale_args=()
          local transform

          if [[ ! "$batch" =~ keyword[[:space:]]+monitor[[:space:]]+([^,]+),transform,([0-9]+) ]]
          then
            return 0
          fi

          monitor="''${BASH_REMATCH[1]}"
          transform="''${BASH_REMATCH[2]}"

          if [[ -n "''${MONITOR_SCALE:-}" ]]
          then
            scale_args=(--scale "''${MONITOR_SCALE}")
          fi

          "${pkgs.wlr-randr}/bin/wlr-randr" \
            --output "$monitor" \
            --transform "$(transform_name "$transform")" \
            "''${scale_args[@]}"
        }

        main() {
          if [[ "$#" -eq 0 ]]
          then
            usage
            return 2
          fi

          if [[ "$1" == "--batch" ]]
          then
            apply_transform "''${2:-}"
            # input:touchdevice/tablet transforms are static in Lua config; ignore.
            # iio-hyprland reads stdout via fgets, so always print "ok".
            printf 'ok\n'
            return 0
          fi

          exec "${pkgs.hyprland}/bin/hyprctl" "$@"
        }

        if [[ "''${BASH_SOURCE[0]}" == "$0" ]]
        then
          main "$@"
        fi

        # vim: ft=bash sw=2 ts=2 sts=2 et
  '';

  # Wrapper script that prepends our hyprctl shim to PATH, then execs iio-hyprland
  iioHyprlandWrapper = pkgs.writeShellScript "iio-hyprland-wrapper" ''
    apply_startup_transform() {
      local tries=20

      while [[ "$tries" -gt 0 ]]
      do
        if ${pkgs.wlr-randr}/bin/wlr-randr --output eDP-1 --transform 270 --scale "${monitorScale}"
        then
          return 0
        fi

        sleep 0.5
        tries=$((tries - 1))
      done

      echo "failed to apply initial eDP-1 transform for gk4" >&2
      return 1
    }

    main() {
      export MONITOR_SCALE="${monitorScale}"
      export PATH="${hyprctlWrapper}/bin:${pkgs.hyprland}/bin:$PATH"

      if [[ -n "${lib.optionalString isGk4 "1"}" ]]
      then
        apply_startup_transform
      fi

      exec ${lib.getExe pkgs.iio-hyprland} --transform 3,0,1,2
    }

    if [[ "''${BASH_SOURCE[0]}" == "$0" ]]
    then
      main "$@"
    fi

    # vim: ft=bash sw=2 ts=2 sts=2 et
  '';
in
{
  systemd.user.services."iio-hyprland" = lib.mkIf osConfig.hardware.sensor.iio.enable {
    Unit = {
      Description = "Automatic display rotation via iio-hyprland";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };

    Service = {
      # NOTE These --transform values are only relevant for the GPD Pocket 4.
      # The wrapper script intercepts hyprctl keyword monitor calls and
      # converts them to wlr-randr for Lua config (non-legacy parser) compat.
      ExecStart = "${iioHyprlandWrapper}";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
