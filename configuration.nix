# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:
let
  unstable = import
    (builtins.fetchTarball "https://github.com/nixos/nixpkgs/tarball/master")
    # reuse the current configuration
    { config = config.nixpkgs.config; };
  flake-compat = builtins.fetchTarball
    "https://github.com/edolstra/flake-compat/archive/master.tar.gz";

  hyprland-flake = (import flake-compat {
    # master
    # src = builtins.fetchTarball "https://github.com/hyprwm/Hyprland/archive/master.tar.gz";
    # release
    src = builtins.fetchTarball
      "https://github.com/hyprwm/Hyprland/releases/download/v0.28.0/source-v0.28.0.tar.gz";
  }).defaultNix;

  waybar-hyprland = pkgs.waybar.overrideAttrs (oldAttrs: {
    mesonFlags = oldAttrs.mesonFlags ++ [ "-Dexperimental=true" ];
  });

  python-packages = ps:
    with ps; [
      dbus-python
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
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ./home-manager.nix
    # sudo nix-channel --add https://github.com/nix-community/home-manager/archive/release-23.05.tar.gz home-manager
    # $ sudo nix-channel --update
    # <home-manager/nixos>
    # ./modules/hacompanion.nix
  ];

  nix = {
    package = pkgs.nixFlakes;
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 10d";
    };
    settings = {
      allowed-users = [ "pschmitt" ];
      experimental-features = [ "nix-command" "flakes" ];
      # Hyprland flake
      substituters = [ "https://hyprland.cachix.org" ];
      trusted-public-keys = [
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      ];
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

  system = {
    # This value determines the NixOS release from which the default
    # settings for stateful data, like file locations and database versions
    # on your system were taken. It‘s perfectly fine and recommended to leave
    # this value at the release version of the first install of this system.
    # Before changing this value read the documentation for this option
    # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
    stateVersion = "23.05"; # Did you read the comment?

    autoUpgrade = {
      enable = true;
      channel = "https://nixos.org/channels/nixos-23.05";
    };
  };

  boot = {
    kernel.sysctl = { "kernel.sysrq" = 1; };

    kernelPackages = pkgs.linuxPackages_latest;
    # Attempt to fix keyboard in initrd on x13
    # kernelParams = [ "i8042.notimeout=1" "i8042.dumbkbd=1" "i8042.reset=1" "i8042.direct=1" ];
    # initrd.availableKernelModules = ["i8042"];
    # initrd.kernelModules = ["i8042"];

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

  # DIRTYFIX Force reload i8042 module on boot
  systemd.services.fix-keyboard = {
    wantedBy = [ "multi-user.target" ];
    description = "Fix keyboard by reloading i8042";
    serviceConfig = {
      Type = "oneshot";
      ExecStartPre- = "${pkgs.kmod}/bin/rmmod i8042";
      ExecStart = "${pkgs.kmod}/bin/modprobe i8042";
    };
  };

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking = {
    hostName = "x13"; # Define your hostname.
    # wireless.enable = true;  # Enables wireless support via wpa_supplicant.
    networkmanager = {
      enable = true;
      dns = "systemd-resolved";
    };

    # Disable the firewall altogether.
    firewall = {
      enable = false;
      # allowedTCPPorts = [ ... ];
      # allowedUDPPorts = [ ... ];
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

    # Enable the GNOME Desktop Environment.
    # desktopManager.gnome.enable = false;
    # displayManager = {
    #   autoLogin = {
    #     enable = true;
    #     user = "pschmitt";
    #   };
    #   gdm = {
    #     enable = false;
    #     wayland = true;  # aint that the default?
    #   };
    # };

    # NOTE This only works for x11 ie. it creates xsession files
    # displayManager.session = [ { manage = "desktop";
    #     name = "xterm";
    #     start = ''
    #       ${pkgs.xterm}/bin/xterm -ls &
    #       waitPID=$!
    #     '';
    #   }
    # ];
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
    settings = {
      # background = {
      #   path = "xxx";
      #   fit = "Contain";
      # };
      GTK = {
        application_prefer_dark_theme = true;
        cursor_theme_name = "Adwaita";
        font_name = "Ubuntu Sans 16";
        icon_theme_name = "Adwaita";
        theme_name = "Adwaita";
      };
      commands = {
        reboot = [ "systemctl" "reboot" ];
        poweroff = [ "systemctl" "poweroff" ];
      };
    };
  };

  # This only works for greetd (without regreet)
  # environment.etc."greetd/environments".text = ''
  #   Hyprland
  #   sway
  #   zsh
  #   ${config.users.users.pschmitt.home}/.config/hypr/bin/hyprland-wrapped.sh
  # '';

  # Below is required for some weird reason when using greetd with autologin
  users.groups.pschmitt = { };

  # Below is required for gtklock-userinfo-module
  services.accounts-daemon.enable = true;

  # Workaround for GNOME autologin: https://github.com/NixOS/nixpkgs/issues/103746#issuecomment-945091229
  # systemd.services."getty@tty1".enable = false;
  # systemd.services."autovt@tty1".enable = false;

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
  programs.dconf.enable = true;

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

  # XDG Portals
  xdg = {
    autostart.enable = true;
    portal = {
      enable = true;
      xdgOpenUsePortal = true;
      extraPortals =
        [ pkgs.xdg-desktop-portal pkgs.xdg-desktop-portal-hyprland ];
    };
  };

  # Enable gtk lock pam auth
  security.pam.services.gtklock = { };

  # Disable password prompts for wheel users when sudo'ing
  security.sudo.wheelNeedsPassword = false;

  # Enable polkit (pkexex)
  security.polkit.enable = true;

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

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.pschmitt = {
    isNormalUser = true;
    description = "Philipp Schmitt";
    extraGroups = [
      "adbusers"
      "docker"
      "mlocate"
      "networkmanager"
      "pschmitt"
      "video"
      "wheel"
    ];
    packages = with pkgs; [ ];
    openssh.authorizedKeys.keys =
      let authorizedKeys = builtins.fetchurl "https://github.com/pschmitt.keys";
      in pkgs.lib.splitString "\n" (builtins.readFile authorizedKeys);
    shell = pkgs.zsh;
  };

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

  # Hyprland
  programs.hyprland = {
    enable = true;
    # comment out line below to use the regular (non-flake) Hyprland version
    package = hyprland-flake.packages.${pkgs.system}.hyprland;
  };

  systemd.user.targets.hyprland-session = {
    description = "Hyprland compositor session";
    documentation = [ "man:systemd.special(7)" ];
    bindsTo = [ "graphical-session.target" ];
    wants = [ "graphical-session-pre.target" ];
    after = [ "graphical-session-pre.target" ];
  };

  programs.adb.enable = true;

  virtualisation.docker = {
    enable = true;
    storageDriver = "btrfs";
    package = unstable.docker_24;
  };

  environment.sessionVariables = rec {
    # GTK_THEME = "Adwaita:dark";
    MOZ_ENABLE_WAYLAND = "1";
    MOZ_USE_XINPUT2 = "1";
  };

  environment.etc = {
    "zshenv.local" = {
      text = ''
        export ZDOTDIR="$HOME/.config/zsh"
      '';
      mode = "0644";
    };
  };

  # Some programs need SUID wrappers, can be configured further or are
  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    # core
    acpi
    bc
    bind # dig
    curl
    dua # ncdu on steroids
    file
    fping
    gobject-introspection
    gparted
    gtk3 # gtk-update-icon-cache
    htop
    jq
    killall
    libsecret # secret-tool
    lm_sensors
    mediainfo
    ncpamixer
    nmap
    nodejs
    pamixer
    pciutils # lspci
    pinentry
    pinentry-curses
    pinentry-gnome
    polkit_gnome
    procps # coreutils' uptime does not have the -s flag
    pstree
    ripgrep
    tailscale
    tmux
    tree
    wget
    xorg.xhost
    yq-go

    # apps
    firefox
    kitty
    usbimager # etcher alternative

    # devel
    cargo
    gcc
    gnumake
    go
    neovim
    pkg-config
    # (python3.withPackages(python-packages))
    (python311.withPackages (python-packages))
    rustc
    openssl

    (vim_configurable.customize {
      name = "vim";
      vimrcConfig.customRC = ''
        set nocompatible
        filetype plugin indent on
        syntax on
        set modeline
        set autoindent expandtab smarttab
        set mouse=a
        scriptencoding utf-8
        set backspace=indent,eol,start
      '';
    })

    # Experiment
    # (writeTextFile {
    #   name = "hyprland-wrapped.desktop";
    #   destination = "/share/wayland-sessions/hyprland-wrapped.desktop";
    #   text = ''
    #     [Desktop Entry]
    #     Name=Hyprland (wrapped)
    #     Comment=Hyprland (wrapped)
    #     Exec=${config.users.users.pschmitt.home}/.config/hypr/bin/hyprland-wrapped.sh
    #     Type=Application
    #   '';
    # })
  ];

  # NOTE You might need to run $ fc-cache -v --really-force as both your user and root
  # Also, removing ~/.config/fontconfig might help in case emojis are all fucked up and shit
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

  # FIXME This seems to break Hyprland (flake)
  programs.nix-ld = {
    enable = true;
    # libraries = [];
  };

  # started in user sessions.
  # programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    pinentryFlavor = "gnome3";
    enableSSHSupport = true;
  };

  programs.tmux = {
    enable = true;
    clock24 = true;
    newSession = true;
    terminal = "tmux-direct";
    aggressiveResize = true;
    # Set prefix to C-a
    shortcut = "a";
    keyMode = "vi";
    # extraConfig = ''
    #   set-option -g mouse on
    #   '';
    plugins = with pkgs; [
      tmuxPlugins.sensible
      tmuxPlugins.pain-control
      tmuxPlugins.onedark-theme
      tmuxPlugins.mode-indicator
      tmuxPlugins.fuzzback # prefix-?
    ];
  };

  programs.npm = {
    enable = true;
    package = pkgs.nodePackages_latest.npm;
    # FIXME This does not seem to be enough to override the dirs npm uses
    # We might need to write this to /usr/etc/npmrc as the Arch Wiki suggests:
    # https://wiki.archlinux.org/title/XDG_Base_Directory
    npmrc = ''
      prefix=''${XDG_DATA_HOME}/npm
      cache=''${XDG_CACHE_HOME}/npm
      init-module=''${XDG_CONFIG_HOME}/npm/config/npm-init.js'
    '';
  };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh = {
    enable = true;
    # require public key authentication for better security
    settings.PasswordAuthentication = true;
    settings.KbdInteractiveAuthentication = true;
    settings.PermitRootLogin = "yes";
  };

  services.tailscale = { enable = true; };
}

# vim: set ft=nix et ts=2 sw=2 :
