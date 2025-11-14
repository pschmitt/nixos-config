{ config, lib, pkgs, ... }:
let
  inherit (lib) escapeShellArgs getExe;
  hypreventsBin = getExe pkgs.hyprevents;
  hyprBinDir = "${config.home.homeDirectory}/.config/hypr/bin";
in
{
  home.packages = [
    pkgs.hyprevents
  ];

  systemd.user.services.hyprevents = {
    Unit = {
      Description = "Hyprland event dispatcher";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };

    Service = {
      ExecStart = escapeShellArgs [
        hypreventsBin
        "--file"
        "${hyprBinDir}/hyprevents-handler.sh"
      ];
      Restart = "on-failure";
      RestartSec = 2;
    };
  };
}
