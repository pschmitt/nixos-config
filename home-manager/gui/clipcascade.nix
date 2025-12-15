{ pkgs, ... }:
{
  systemd.user.services.clipcascade = {
    Unit = {
      Description = "ClipCascade clipboard sync";
      After = [
        "graphical-session.target"
        "network-online.target"
      ];
      Wants = [ "network-online.target" ];
      PartOf = [ "graphical-session.target" ];
    };

    Service = {
      ExecStart = "${pkgs.clipcascade}/bin/clipcascade";
      Restart = "on-failure";
      RestartSec = 5;
    };

    Install.WantedBy = [ "graphical-session.target" ];
  };
}
