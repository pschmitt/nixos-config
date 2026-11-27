{ lib, pkgs, ... }:
{
  home.packages = [ pkgs.mickey ];

  systemd.user.services.mickey = {
    Unit = {
      Description = "Mickey keyboard and mouse sharing";
      PartOf = [ "graphical-session.target" ];
      After = [
        "graphical-session.target"
        "mickey-trial.service"
      ];
      Conflicts = [ "mickey-trial.service" ];
    };

    Service = {
      ExecStart = "${lib.getExe pkgs.mickey} run";
      Restart = "on-failure";
      RestartSec = 3;
    };

    Install.WantedBy = [ "graphical-session.target" ];
  };
}
