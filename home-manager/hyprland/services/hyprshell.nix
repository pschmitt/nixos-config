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
      overview = {
        enable = false;
        key = "super_l";
        modifier = "super";
        launcher = {
          show_when_empty = true;
        };
      };
      switch = {
        enable = true;
        modifier = "super";
        filter_by = [ ];
      };
    };
  };
}
