{ config, pkgs, ... }:
let
  quickshellBar = pkgs.quickshell-bar.override { enableSoftKeyboard = config.host.touchscreen; };
in
{
  home.packages = [ quickshellBar ];

  systemd.user.services.quickshell-bar = {
    Unit = {
      Description = "Custom Quickshell top bar (Waybar alternative)";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };

    Service = {
      ExecStart = "${quickshellBar}/bin/quickshell-bar";
      Restart = "on-failure";
      RestartSec = 5;
    };

    # Not in Install.wantedBy: opt-in only, Waybar remains the default bar.
  };
}
