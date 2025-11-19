{ pkgs, ... }:
let
  target = "graphical-session.target";
in
{
  home.packages = [
    pkgs.wl-clipboard
  ];

  services.cliphist = {
    enable = true;
    allowImages = true;
    systemdTargets = [ target ];
  };

  services.wl-clip-persist = {
    enable = true;
    clipboardType = "both";
    systemdTargets = [ target ];
  };
}
