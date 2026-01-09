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
    # terminals
    alacritty
    foot
    pkgs.master.kitty
    inputs.ghostty.packages.${pkgs.stdenv.hostPlatform.system}.default
    inputs.wezterm.packages.${pkgs.stdenv.hostPlatform.system}.default

    # files and docs
    eog
    evince
    ffmpegthumbnailer # for video thumbnails in nautilus
    file-roller
    gnome-font-viewer
    imv # image viewer
    nautilus
    sushi # file previewer for gnome

    # wayland
    wayvnc
    wdisplays
    wlr-randr

    # input emulation
    dotool
    inputs.lan-mouse.packages.${pkgs.stdenv.hostPlatform.system}.default
    libinput # libinput debug-events
    wlrctl
    wtype
    ydotool

    # secrets
    libsecret # secret-tool
    pinentry-curses
    pinentry-gnome3

    # misc apps
    gparted
    remmina
    usbimager # etcher alternative
    virt-manager

    # images
    chafa
    qrencode
    tesseract
    zbar # provides zbarimg, for reading qr codes
  ];
}

# vim: set ft=nix et ts=2 sw=2 :
