{ inputs, pkgs, ... }:
let
  weztermPkg = inputs.wezterm.packages.${pkgs.system}.default;
in
{
  environment.systemPackages = with pkgs; [
    alacritty
    foot
    kitty
    weztermPkg
    lan-mouse

    # files and docs
    gnome.eog
    gnome.evince
    gnome.gnome-font-viewer
    gnome.file-roller
    gnome.nautilus
    gnome.seahorse
    gnome.sushi
    imv # image viewer
    zathura

    # wayland
    lemonade
    nwg-displays
    remmina
    wayvnc
    wdisplays
    wlr-randr
    wlrctl

    # input emulation
    dotool
    wtype
    ydotool
  ];
}

# vim: set ft=nix et ts=2 sw=2 :
