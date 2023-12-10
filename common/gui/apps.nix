{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    alacritty
    foot
    kitty
    # wezterm  # og package, from upstream nixpkgs
    # wezterm-bin
    wezterm-nightly

    # files and docs
    gnome.eog
    gnome.evince
    gnome.gnome-font-viewer
    gnome.file-roller
    gnome.nautilus
    gnome.seahorse
    gnome.sushi

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
