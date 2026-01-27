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
    # NOTE Setting the clipboardType to "both" causes issues with GTK apps such
    # nautilus and meld where text becomes impossible to select.
    # https://github.com/hyprwm/Hyprland/issues/2619
    clipboardType = "regular";
    systemdTargets = [ target ];
  };
}
