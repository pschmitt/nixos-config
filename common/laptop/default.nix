# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ inputs, lib, config, pkgs, ... }:
let
  # https://www.reddit.com/r/NixOS/comments/14rhsnu/regreet_greeter_for_greetd_doesnt_show_a_session/
  regreet-override = pkgs.greetd.regreet.overrideAttrs (final: prev: {
    SESSION_DIRS = "${config.services.xserver.displayManager.sessionData.desktops}/share";
  });

  python-packages = ps:
    with ps; [
      # ansible
      dbus-python
      dnspython
      black
      flake8
      gst-python
      ipython
      isort
      pip
      pipx
      pygobject3
      pynvim
      requests
      rich
    ];

in
{
  imports = [
    # ./hardware-configuration.nix
    ../../home-manager
    ./btrfs.nix
    ./hyprland.nix
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
      allowed-users = [ "pschmitt" ];
      # experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = true;
    };
  };

  nixpkgs = {
    # Allow unfree packages
    config.allowUnfree = true;

    overlays = with pkgs; [
      (self: super: {
        mpv-unwrapped =
          super.mpv-unwrapped.override { ffmpeg_5 = ffmpeg_5-full; };
      })
    ];
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

    # Bootloader.
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;

    # Setup keyfile
    # initrd.secrets = {
    #   "/crypto_keyfile.bin" = null;
    # };

    tmp = { useTmpfs = true; };
  };

  # Enable networking
  networking = {
    networkmanager = {
      enable = true;
      dns = "systemd-resolved";
    };
  };

  # FIXME Disable wait-online services, this somehow results in NM not being started at all.
  # systemd.network.wait-online.enable = false;
  # systemd.services.NetworkManager-wait-online.enable = false;

  services.resolved = {
    enable = true;
    dnssec = "true";
    llmnr = "true";
    # domains = [ "~." ];
    fallbackDns = [ "1.1.1.1#one.one.one.one" "1.0.0.1#one.one.one.one" ];
    extraConfig = ''
      DNSOverTLS=opportunistic
      MulticastDNS=yes
    '';
  };

  hardware.bluetooth = {
    enable = true;
    # settings = {
    #   General = {
    #     Enable = "Source,Sink,Media,Socket";
    #   };
    # };
  };
  services.blueman.enable = true;

  # Set your time zone.
  time.timeZone = "Europe/Berlin";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "de_DE.UTF-8";
    LC_IDENTIFICATION = "de_DE.UTF-8";
    LC_MEASUREMENT = "de_DE.UTF-8";
    LC_MONETARY = "de_DE.UTF-8";
    LC_NAME = "de_DE.UTF-8";
    LC_NUMERIC = "de_DE.UTF-8";
    LC_PAPER = "de_DE.UTF-8";
    LC_TELEPHONE = "de_DE.UTF-8";
    LC_TIME = "de_DE.UTF-8";
  };

  # Configure console keymap
  console.keyMap = "de";

  services.xserver = {
    # Enable the X11 windowing system.
    enable = true;
    layout = "de";
    xkbVariant = "";
    # Enable touchpad support (enabled default in most desktopManager).
    libinput.enable = true;
  };

  # https://nixos.wiki/wiki/Greetd
  services.greetd = {
    enable = true;
    restart = false; # Restart greetd when it crashes
    settings = rec {
      initial_session = {
        # command = "${pkgs.hyprland}/bin/Hyprland";
        # command = "${hyprland-flake.packages.${pkgs.system}.hyprland}/bin/Hyprland";
        command =
          "${config.users.users.pschmitt.home}/.config/hypr/bin/hyprland-wrapped.sh";
        user = "pschmitt";
      };
      default_session = {
        # command = "/nix/store/pv33drl44ry54dvi0d0rnva3ybwgid5r-dbus-1.14.8/bin/dbus-run-session /nix/store/jccwacv61ifyblaqz37wnlq7b2q82ax3-cage-0.1.4/bin/cage -s -- /nix/store/d9x7bvhvlyqnz6331mv0lsl2mya4c433-regreet-0.1.0/bin/regreet"
        command =
          "${pkgs.dbus}/bin/dbus-run-session ${pkgs.cage}/bin/cage -s -- ${pkgs.greetd.regreet}/bin/regreet";
        user = "greeter";
      };
    };
  };

  programs.regreet = {
    enable = true;
    package = regreet-override;
    settings = {
      # background = {
      #   path = "xxx";
      #   fit = "Contain";
      # };
      GTK = {
        application_prefer_dark_theme = true;
        cursor_theme_name = "Adwaita";
        font_name = "Noto Sans 16";
        icon_theme_name = "Adwaita";
        theme_name = "Adwaita";
      };
      commands = {
        reboot = [ "systemctl" "reboot" ];
        poweroff = [ "systemctl" "poweroff" ];
      };
    };
  };

  # Below is required for some weird reason when using greetd with autologin
  users.groups.pschmitt = { };

  services.udev.packages = [ pkgs.android-udev-rules ];

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # mlocate
  services.locate = {
    enable = true;
    locate = pkgs.plocate;
    interval = "daily";
    localuser = null; # scan as root
  };

  # enable sushi and keyring
  services.gnome = {
    sushi.enable = true;
    gnome-keyring.enable = true;
    rygel.enable = true;
  };

  systemd = {
    user.services.polkit-gnome-authentication-agent-1 = {
      description = "polkit-gnome-authentication-agent-1";
      wantedBy = [ "graphical-session.target" ];
      wants = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart =
          "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
        Restart = "on-failure";
        RestartSec = 1;
        TimeoutStopSec = 10;
      };
    };
  };

  services.dbus = {
    enable = true;
    packages = [ pkgs.gcr ];
  };
  services.gvfs.enable = true;
  services.tumbler.enable = true;

  # Disable password prompts for wheel users when sudo'ing
  security.sudo.wheelNeedsPassword = false;

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

  # firmware updates
  services.fwupd.enable = true;

  # Enable flatpak
  services.flatpak.enable = true;

  # temporary hack until official lingering support is added to `users.users`
  # https://github.com/NixOS/nixpkgs/issues/3702
  systemd.tmpfiles.rules = [
    "f /var/lib/systemd/linger/pschmitt"
  ];

  programs.zsh.enable = true;
  environment.shells = with pkgs; [ zsh ];

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = false;
    vimAlias = true;
    configure = {
      extraConfig = ''
        set nocompatible
        filetype plugin indent on
        syntax on
        set modeline
        set autoindent expandtab smarttab
        set mouse=a
        scriptencoding utf-8
        set backspace=indent,eol,start
        set number
        set listchars=tab:→\ ,space:·,nbsp:␣,trail:•,eol:¶,precedes:«,extends:»
      '';
      # packages.myVimPackage = with pkgs.vimPlugins; {
      #   # loaded on launch
      #   start = [ fugitive ];
      #   # manually loadable by calling `:packadd $plugin-name`
      #   opt = [ ];
      # };
    };
  };

  programs.adb.enable = true;

  programs.firefox = {
    enable = true;
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
    libinput # libinput debug-events
    libsecret # secret-tool
    pinentry-curses
    pinentry-gnome
    polkit_gnome
    tesseract

    # media
    ncpamixer
    pamixer
    pavucontrol
    pulseaudio # pactl + pacmd

    # apps
    audacity
    firefox
    google-chrome
    gparted
    kitty
    mullvad-vpn
    usbimager # etcher alternative
  ];

  # NOTE You might need to run $ fc-cache -v --really-force as both your user and root
  # Also, removing ~/.config/fontconfig might help in case emojis are all fucked up and shit
  # The last time around the following command fixed emojis in pango apps:
  # rm -rf ~/.cache/fontconfig ~/.config/fontconfig; sudo fc-cache --really-force -v; fc-cache --really-force -v
  fonts = {
    fonts = with pkgs; [
      # (nerdfonts.override { fonts = [ "FiraCode" "DroidSansMono" ]; })
      # dejavu_fonts
      # noto-fonts-cjk
      fira-code
      fira-code-symbols
      liberation_ttf
      noto-fonts
      noto-fonts-emoji
      nerdfonts
      ubuntu_font_family
    ];
    fontDir.enable = true;
    enableDefaultFonts = true;
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

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh = {
    enable = true;
    # require public key authentication for better security
    settings.PasswordAuthentication = true;
    settings.KbdInteractiveAuthentication = true;
    settings.PermitRootLogin = "prohibit-password";
  };

  services.tailscale = { enable = true; };
}

# vim: set ft=nix et ts=2 sw=2 :
