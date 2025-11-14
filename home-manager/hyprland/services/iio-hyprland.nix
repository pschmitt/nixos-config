{
  lib,
  osConfig ? null,
  pkgs,
  ...
}:
let
  hostName = if osConfig == null then null else (osConfig.networking.hostName or null);
  isGk4 = hostName == "gk4";
  iioHyprlandBin = lib.getExe pkgs.iio-hyprland;
in
{
  systemd.user.services."iio-hyprland" = lib.mkIf isGk4 {
    Unit = {
      Description = "Automatic display rotation via iio-hyprland";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };

    Service = {
      ExecStart = "${iioHyprlandBin} --transform 3,0,1,2";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
