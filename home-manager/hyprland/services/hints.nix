{ lib, pkgs, ... }:
let
  hintsd = lib.getExe' pkgs.hints "hintsd";
in
{
  systemd.user.services.hintsd = {
    Unit = {
      Description = "Hintsd service";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };

    Service = {
      ExecStart = hintsd;
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
