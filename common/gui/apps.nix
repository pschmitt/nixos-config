{ inputs, pkgs, ... }:
{
  # https://app.cachix.org/cache/lan-mouse
  nix.settings = {
    # lan-mouse flake
    substituters = [
      "https://ghostty.cachix.org"
      "https://lan-mouse.cachix.org"
    ];
    trusted-public-keys = [
      "ghostty.cachix.org-1:QB389yTa6gTyneehvqG58y0WnHjQOqgnA+wBnpWWxns="
      "lan-mouse.cachix.org-1:KlE2AEZUgkzNKM7BIzMQo8w9yJYqUpor1CAUNRY6OyM="
    ];
  };

  environment.systemPackages = with pkgs; [
    alacritty
    foot
    pkgs.master.kitty
    inputs.ghostty.packages.${pkgs.system}.default
    inputs.wezterm.packages.${pkgs.system}.default
    inputs.lan-mouse.packages.${pkgs.system}.default

    # files and docs
    eog
    evince
    gnome-font-viewer
    file-roller
    nautilus
    sushi
    imv # image viewer
    zathura

    # wayland
    lemonade
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
