{ pkgs, ... }:
{
  systemd.user.services.hypr-snap-preview = {
    Unit = {
      Description = "Hyprland window snap preview";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Install.WantedBy = [ "graphical-session.target" ];
    Service = {
      ExecStart = "${pkgs.quickshell}/bin/quickshell -p ${./snap-preview.qml}";
      Restart = "on-failure";
    };
  };
}
