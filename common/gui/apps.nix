{ inputs, pkgs, ... }:
{
  # https://app.cachix.org/cache/lan-mouse
  nix.settings = {
    # lan-mouse flake
    substituters = [ "https://lan-mouse.cachix.org" ];
    trusted-public-keys = [ "lan-mouse.cachix.org-1:KlE2AEZUgkzNKM7BIzMQo8w9yJYqUpor1CAUNRY6OyM=" ];
  };

  environment.systemPackages = with pkgs; [
    alacritty
    foot
    kitty
    inputs.wezterm.packages.${pkgs.system}.default
    inputs.lan-mouse.packages.${pkgs.system}.default

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
