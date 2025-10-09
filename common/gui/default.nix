{ config, pkgs, ... }:
{
  imports = [
    ./apps.nix
    ./audio.nix
    ./browser.nix
    ./bluetooth.nix
    ./btrfs.nix
    ./fonts.nix
    ./gnome-keyring.nix
    ./gpu.nix
    ./go-hass-agent.nix
    ./hacompanion.nix
    ./libvirt.nix
    ./logitech-mouse.nix
    ./podsync-cookies.nix
    ./printer.nix
    ./theme.nix

    # Display Manager
    ./gdm.nix
    # ./greetd.nix

    # Desktops
    ./gnome.nix
    ./hyprland.nix
    ./sway.nix
  ];

  boot = {
    extraModulePackages = [ config.boot.kernelPackages.v4l2loopback ];
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

  services = {
    avahi = {
      enable = true;
      nssmdns4 = true;
    };

    dbus = {
      enable = true;
      implementation = "broker";
    };

    # enable sushi and rygel
    gnome = {
      sushi.enable = true;
      rygel.enable = true;
    };

    gvfs.enable = true;
    seatd.enable = true;
    tumbler.enable = true;
    udev.packages = [ pkgs.android-udev-rules ];
  };

  # Enable lingering
  systemd.tmpfiles.rules = [ "f /var/lib/systemd/linger/${config.custom.username}" ];
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
    deckmaster
    imagemagick
    yt-dlp

    # apps
    gparted
    mullvad-vpn
    usbimager # etcher alternative
    virt-manager

    # qrcode create/read
    qrencode
    zbar # provides zabarimg, for reading qr codes

    # cli image viewers
    chafa
    # termimage
  ];
}

# vim: set ft=nix et ts=2 sw=2 :
