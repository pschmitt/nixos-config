{ inputs, pkgs, ... }:
let
  hyprshellPkg = inputs.hyprshell.packages.${pkgs.stdenv.hostPlatform.system}.hyprshell;
in
{
  imports = [
    inputs.hyprshell.homeModules.hyprshell
  ];

  programs.hyprshell = {
    enable = true;
    package = hyprshellPkg;
    systemd.target = "graphical-session.target";
    settings.windows = {
      enable = true;
      switch = {
        enable = true;
        modifier = "super";
      };
    };
  };
}
