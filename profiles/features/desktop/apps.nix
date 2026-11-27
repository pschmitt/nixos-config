{ inputs, pkgs, ... }:
{
  nix.settings = {
    extra-substituters = [
      "https://ghostty.cachix.org"
    ];
    trusted-public-keys = [
      "ghostty.cachix.org-1:QB389yTa6gTyneehvqG58y0WnHjQOqgnA+wBnpWWxns="
    ];
  };

  environment.systemPackages = with pkgs; [
    # terminals
    alacritty
    foot
    pkgs.master.kitty
    inputs.ghostty.packages.${pkgs.stdenv.hostPlatform.system}.default
    wezterm

    # files and docs
    evince
    ffmpegthumbnailer # for video thumbnails in nautilus
    file-roller
    gnome-font-viewer
    imv # image viewer
    loupe
    nautilus
    nautilus-python
    sushi # file previewer for gnome

    # wayland
    wayvnc
    wdisplays
    wlr-randr

    # input emulation
    dotool
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
    timg
    zbar # provides zbarimg, for reading qr codes
  ];
}

# vim: set ft=nix et ts=2 sw=2 :
