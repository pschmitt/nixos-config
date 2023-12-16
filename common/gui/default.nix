{ inputs, lib, config, pkgs, ... }: {
  imports = [
    # ./hardware-configuration.nix
    ./apps.nix
    ./bluetooth.nix
    ./btrfs.nix
    ./gec-vpn.nix
    ./hacompanion.nix
    ./hyprland.nix
    ./libvirt.nix
    ./logitech-mouse.nix
    ./soundboard.nix
    ./theme.nix
  ];

  nix = {
    # package = pkgs.nixFlakes;

    # This will add each flake input as a registry
    # To make nix3 commands consistent with your flake
    registry = lib.mapAttrs (_: value: { flake = value; }) inputs;

    # This will additionally add your inputs to the system's legacy channels
    # Making legacy nix commands consistent as well, awesome!
    nixPath = lib.mapAttrsToList (key: value: "${key}=${value.to.path}") config.nix.registry;

    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 10d";
    };
    settings = {
      allowed-users = [ config.custom.username ];
      # experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = true;
    };
  };

  nixpkgs = {
    # Allow unfree packages
    config.allowUnfree = true;
  };

  boot = {
    extraModulePackages = [ pkgs.linuxPackages_latest.v4l2loopback ];
    # Explicitly load i8042 to attempt to fix the x13 keyboard in initrd
    kernelModules = [ "v4l2loopback" ];
    extraModprobeConfig = ''
      # exclusive_caps: Skype, Zoom, Teams etc. will only show device when actually streaming
      # card_label: Name of virtual camera, how it'll show up in Skype, Zoom, Teams
      # https://github.com/umlaeute/v4l2loopback
      options v4l2loopback video_nr=10 exclusive_caps=1 card_label="OBS Virtual Camera"
    '';
  };

  services.xserver = {
    # Enable the X11 windowing system.
    enable = true;
    layout = "de";
    xkbVariant = "";
    # Enable touchpad support (enabled default in most desktopManager).
    libinput.enable = true;
  };

  hardware.uinput.enable = true;
  services.udev.packages = [ pkgs.android-udev-rules ];

  # enable sushi and keyring
  services.gnome = {
    sushi.enable = true;
    gnome-keyring.enable = true;
    rygel.enable = true;
  };

  services.dbus = {
    enable = true;
    packages = [ pkgs.gcr ];
  };
  services.gvfs.enable = true;
  services.tumbler.enable = true;

  # Enable sound with pipewire.
  sound.enable = true;
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable lingering
  users.users.pschmitt.linger = true;

  programs.adb.enable = true;

  programs.firefox = {
    enable = true;
    package = pkgs.unstable.firefox;
    # FIXME This does not seem to work.
    # See home-manager/home.nix for the dirty but working solution.
    nativeMessagingHosts.packages = with pkgs; [
      brotab
      config.nur.repos.wolfangaukang.vdhcoapp
      tridactyl-native
    ];
    preferences = {
      # Enable custom css (userChrome.css)
      "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
      # Hide share indicator
      "privacy.webrtc.legacyGlobalIndicator" = false;
      "privacy.webrtc.hideGlobalIndicator" = true;
      # Prevent Firefox from Googling .lan addresses and opening them directly
      "browser.fixup.domainsuffixwhitelist.lan" = true;
    };
    preferencesStatus = "user";
  };

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
    pinentry-gnome
    tesseract

    # media
    imagemagick
    ncpamixer
    pamixer
    pavucontrol
    pulseaudio # pactl + pacmd
    deckmaster
    yt-dlp
    (sox.override { enableLame = true; enableAMR = true; })

    # apps
    audacity
    firefox
    google-chrome
    gparted
    kitty
    mullvad-vpn
    usbimager # etcher alternative
    virt-manager

    intel-gpu-tools
    piper # gui for libratbag

    # audio
    helvum
    qpwgraph
  ];

  # NOTE You might need to run $ fc-cache -v --really-force as both your user and root
  # Also, removing ~/.config/fontconfig might help in case emojis are all fucked up and shit
  # The last time around the following command fixed emojis in pango apps:
  # rm -rf ~/.cache/fontconfig ~/.config/fontconfig; sudo fc-cache --really-force -v; fc-cache --really-force -v
  fonts = {
    packages = with pkgs; [
      # dejavu_fonts
      # noto-fonts-cjk
      fira-code
      fira-code-symbols
      liberation_ttf
      nerdfonts
      noto-fonts
      noto-fonts-emoji
      ubuntu_font_family
      font-awesome
      font-awesome_5

      # proprietary fonts
      ComicCode
      ComicCodeNF
      MonoLisa
      MonoLisa-Custom
      MonoLisa-CustomNF
    ];
    fontDir.enable = true;
    # enableDefaultFonts = true;  # deprecated in unstable
    enableDefaultPackages = true; # new option name (unstable)
    enableGhostscriptFonts = true;
    fontconfig = {
      enable = true;
      antialias = true;
      hinting.enable = true;
      # defaultFonts = {
      #   serif = ["Noto Serif"];
      #   sansSerif = ["Noto Sans"];
      #   monospace = ["Comic Code Nerd Font"];
      #   emoji = ["Noto Color Emoji"];
      # };
    };
  };
}

# vim: set ft=nix et ts=2 sw=2 :
