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
    eog
    evince
    gnome-font-viewer
    file-roller
    nautilus
    seahorse
    sushi
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
