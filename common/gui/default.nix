{ config, pkgs, ... }:
{
  imports = [
    # ./hardware-configuration.nix
    ./apps.nix
    ./audio.nix
    ./browser.nix
    ./bluetooth.nix
    ./btrfs.nix
    ./fonts.nix
    ./hacompanion.nix
    ./hyprland.nix
    ./libvirt.nix
    ./logitech-mouse.nix
    ./printer.nix
    ./theme.nix
  ];

  boot = {
    extraModulePackages = [ config.boot.kernelPackages.v4l2loopback ];
    # Explicitly load i8042 to attempt to fix the x13 keyboard in initrd
    kernelModules = [ "v4l2loopback" ];
    extraModprobeConfig = ''
      # exclusive_caps: Skype, Zoom, Teams etc. will only show device when actually streaming
      # card_label: Name of virtual camera, how it'll show up in Skype, Zoom, Teams
      # https://github.com/umlaeute/v4l2loopback
      options v4l2loopback video_nr=10 exclusive_caps=1 card_label="OBS Virtual Camera"
    '';
  };

  # Enable flatpak
  xdg.portal.enable = true; # required for flatpak
  xdg.portal.xdgOpenUsePortal = true; # fix xdg-open
  services.flatpak = {
    enable = true;
    remotes = {
      "flathub" = "https://dl.flathub.org/repo/flathub.flatpakrepo";
      "flathub-beta" = "https://dl.flathub.org/beta-repo/flathub-beta.flatpakrepo";
    };
    packages = [ ];
  };

  services.xserver = {
    # Enable the X11 windowing system.
    enable = true;
    xkb = {
      layout = "de";
      variant = "";
    };
  };

  hardware.uinput.enable = true;
  # Enable touchpad support (enabled default in most desktopManager).
  services.libinput.enable = true;
  services.udev.packages = [ pkgs.android-udev-rules ];

  # enable sushi and keyring
  services.gnome = {
    sushi.enable = true;
    gnome-keyring.enable = true;
    rygel.enable = true;
  };

  services.avahi = {
    enable = true;
    nssmdns4 = true;
  };

  services.dbus = {
    enable = true;
    packages = [ pkgs.gcr ];
  };
  services.gvfs.enable = true;
  services.tumbler.enable = true;

  # Enable lingering
  systemd.tmpfiles.rules = [ "f /var/lib/systemd/linger/pschmitt" ];
  users.users."${config.custom.username}" = {
    linger = true;

    extraGroups = [
      "adbusers"
      "input" # do we need this?
      "uinput" # for dotool
      "video" # do we need this?
    ];
  };

  programs.adb.enable = true;

  # Some programs need SUID wrappers, can be configured further or are
  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    gobject-introspection
    gtk3 # gtk-update-icon-cache
    iw
    libinput # libinput debug-events
    libsecret # secret-tool
    pinentry-curses
    pinentry-gnome3
    tesseract

    # media
    imagemagick
    deckmaster
    yt-dlp

    # apps
    gparted
    mullvad-vpn
    usbimager # etcher alternative
    virt-manager

    intel-gpu-tools
    piper # gui for libratbag

    # qrcode create/read
    qrencode
    termimage # for displaying the qrcode in cli
    zbar # provides zabarimg, for reading
  ];
}

# vim: set ft=nix et ts=2 sw=2 :
