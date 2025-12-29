{ pkgs, ... }:
{
  systemd.user.services.quickshell-overview = {
    Unit = {
      Description = "https://github.com/Shanu-Kumawat/quickshell-overview";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };

    Service = {
      ExecStart = "${pkgs.quickshell-overview}/bin/quickshell-overview";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  wayland.windowManager.hyprland.settings = {
    bind = [ "$mod, tab, exec, ${pkgs.quickshell-overview}/bin/quickshell-overview-ipc" ];

    # dim around the preview
    decoration = {
      dim_around = 0.8;
    };
    # layerrule = "dimaround, quickshell:overview";
  };
}
