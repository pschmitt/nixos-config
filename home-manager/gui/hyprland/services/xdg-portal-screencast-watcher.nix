{ config, ... }:
let
  hyprBinDir = "${config.home.homeDirectory}/.config/hypr/bin";
in
{
  systemd.user.services."xdg-portal-screencast-watcher" = {
    Unit = {
      Description = "Watch for xdg-portal screencast issues";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };

    Service = {
      ExecStart = "${hyprBinDir}/xdg-portal-screencast-watcher.sh";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
