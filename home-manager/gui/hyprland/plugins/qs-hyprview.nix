{ pkgs, ... }:
{
  systemd.user.services.qs-hyprview = {
    Unit = {
      Description = "https://github.com/dom0/qs-hyprview";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };

    Service = {
      ExecStart = "${pkgs.qs-hyprview}/bin/qs-hyprview";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  wayland.windowManager.hyprland.settings = {
    bind = [ "$mod, tab, exec, ${pkgs.qs-hyprview}/bin/qs-hyprview-ipc smartgrid" ];

    # dim around the preview
    decoration = {
      dim_around = 0.8;
    };
    # FIXME This yields a condfiguration error in Hyprland 0.53.0
    # layerrule = "dim_around, on, quickshell:expose";
  };
}
