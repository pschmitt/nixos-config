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
    inputs.ghostty.packages.${pkgs.stdenv.hostPlatform.system}.default
    inputs.wezterm.packages.${pkgs.stdenv.hostPlatform.system}.default
    inputs.lan-mouse.packages.${pkgs.stdenv.hostPlatform.system}.default

    # files and docs
    eog
    evince
    ffmpegthumbnailer # for video thumbnails in nautilus
    file-roller
    gnome-font-viewer
    imv # image viewer
    nautilus
    sushi
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

    gobject-introspection
    gtk3 # gtk-update-icon-cache
    iw
    libinput # libinput debug-events
    libsecret # secret-tool
    pinentry-curses
    pinentry-gnome3
    tesseract

    # apps
    gparted
    usbimager # etcher alternative
    virt-manager

    # vpn
    tor-browser
    mullvad-vpn

    # qrcode create/read
    qrencode
    zbar # provides zabarimg, for reading qr codes

    # cli image viewers
    chafa
    # termimage
  ];

  programs.adb.enable = true;
}

# vim: set ft=nix et ts=2 sw=2 :
