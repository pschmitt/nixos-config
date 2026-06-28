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
  baseTransform =
    if config.host.internalMonitor.transform != null then config.host.internalMonitor.transform else 0;
  transformMap =
    if config.host.internalMonitor.iioTransformMap != null then
      config.host.internalMonitor.iioTransformMap
    else if baseTransform == 0 then
      [
        0
        1
        2
        3
      ]
    else if baseTransform == 1 then
      [
        1
        2
        3
        0
      ]
    else if baseTransform == 2 then
      [
        2
        3
        0
        1
      ]
    else
      [
        3
        0
        1
        2
      ];
  transformArg = lib.concatMapStringsSep "," toString transformMap;
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

      # iio-hyprland still shells out to `hyprctl keyword ...`, which broke once
      # this setup migrated to Hyprland's Lua config. Prepend a service-local
      # hyprctl shim that rewrites just those old transform updates to `eval`.
      ExecStart = "${lib.getExe pkgs.iio-hyprland} --transform ${transformArg}";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
