{
  lib,
  osConfig,
  pkgs,
  ...
}:
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
      # NOTE These --transform values are only relevant for the GPD Pocket 4
      ExecStart = "${lib.getExe pkgs.iio-hyprland} --transform 3,0,1,2";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
