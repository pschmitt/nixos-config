{
  config,
  lib,
  pkgs,
  ...
}:
let
  hyprctlIioCompat = pkgs.writeShellApplication {
    name = "hyprctl";
    text = builtins.readFile ./scripts/hyprctl-iio-compat.sh;
  };
in
{
  systemd.user.services."iio-hyprland" = lib.mkIf config.host.iioSensor {
    Unit = {
      Description = "Automatic display rotation via iio-hyprland";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };

    Service = {
      Environment = [
        "PATH=${
          lib.makeBinPath [
            hyprctlIioCompat
            pkgs.jq
          ]
        }:/run/current-system/sw/bin"
        "HYPRCTL_REAL=/run/current-system/sw/bin/hyprctl"
      ];

      # NOTE These --transform values are only relevant for the GPD Pocket 4.
      # iio-hyprland still shells out to `hyprctl keyword ...`, which broke once
      # this setup migrated to Hyprland's Lua config. Prepend a service-local
      # hyprctl shim that rewrites just those old transform updates to `eval`.
      ExecStart = "${lib.getExe pkgs.iio-hyprland} --transform 3,0,1,2";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
