# This is your system's configuration file.
# Use this to configure your system environment (it replaces /etc/nixos/configuration.nix)

{ inputs, outputs, lib, config, pkgs, ... }:
let
  python-packages = ps: with ps; [
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
    ./appimage.nix
    ./printer.nix
  ];

  nixpkgs = {
    # You can add overlays here
    overlays = [
      # Add overlays your own flake exports (from overlays and pkgs dir):
      outputs.overlays.additions
      outputs.overlays.modifications
      outputs.overlays.unstable-packages
      outputs.overlays.old-packages

      # You can also add overlays exported from other flakes:
      # neovim-nightly-overlay.overlays.default

      # Or define it inline, for example:
      # (final: prev: {
      #   hi = final.hello.overrideAttrs (oldAttrs: {
      #     patches = [ ./change-hello-to-hi.patch ];
      #   });
      # })
    ];
    # Configure your nixpkgs instance
    config = {
      # Disable if you don't want unfree packages
      allowUnfree = true;
    };
  };

  nix = {
    # This will add each flake input as a registry
    # To make nix3 commands consistent with your flake
    registry = lib.mapAttrs (_: value: { flake = value; }) inputs;

    # This will additionally add your inputs to the system's legacy channels
    # Making legacy nix commands consistent as well, awesome!
    nixPath = lib.mapAttrsToList (key: value: "${key}=${value.to.path}") config.nix.registry;


    settings = {
      # Enable flakes and new 'nix' command
      experimental-features = "nix-command flakes";
      # Deduplicate and optimize nix store
      auto-optimise-store = true;
      trusted-users = [ "root" config.custom.username ];
    };
  };

  boot = {
    # Enable all MagicSysRq keys
    kernel.sysctl = { "kernel.sysrq" = 1; };
    kernelPackages = pkgs.linuxPackages_latest;
    tmp = { useTmpfs = true; };

    # Bootloader.
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;

    # Setup keyfile
    # initrd.secrets = {
    #   "/crypto_keyfile.bin" = null;
    # };
  };

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

  # Enable networking
  networking = {
    networkmanager = {
      enable = true;
      dns = "systemd-resolved";
      # enableFccUnlock = true;  # deprecated
    };
  };

  # FIXME Disable wait-online services, this somehow results in NM not being started at all.
  # systemd.network.wait-online.enable = false;
  # systemd.services.NetworkManager-wait-online.enable = false;

  services.resolved = {
    enable = true;
    dnssec = "false";
    llmnr = "true";
    # domains = [ "~." ];
    fallbackDns = [ "1.1.1.1#one.one.one.one" "1.0.0.1#one.one.one.one" ];
    extraConfig = ''
      DNSOverTLS=opportunistic
      MulticastDNS=yes
    '';
  };

  environment.systemPackages = with pkgs; [
    # nix
    inputs.agenix.packages.${system}.default
    nix-prefetch-git

    # core
    acpi
    autossh
    bc
    bind # dig
    curl
    dua # ncdu on steroids
    file
    fping
    fx
    htop
    hwatch
    jq
    killall
    lm_sensors
    mediainfo
    moreutils # ts among others
    ncdu
    nethogs
    nmap
    ookla-speedtest
    p7zip
    pciutils # lspci
    pinentry-curses
    procps # coreutils' uptime does not have the -s flag
    psmisc # pstree, killall, fuser
    pwgen
    ripgrep
    socat
    sshpass
    tailscale
    tmux
    tree
    ugrep
    unzip
    usbutils # lsusb
    wget
    yq-go
    zip

    # devel
    cargo
    gcc
    gnumake
    go
    neovim
    nodejs
    podman-compose
    pkg-config
    # (python3.withPackages(python-packages))
    # (python310.withPackages(python-packages))
    (python311.withPackages (python-packages))
    unstable.rustc
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
  ];

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.pschmitt = {
    isNormalUser = true;
    description = "Philipp Schmitt";
    extraGroups = [
      "adbusers"
      "docker"
      "input"
      "uinput" # for *dotool
      "libvirtd"
      "mlocate"
      "networkmanager"
      "pschmitt"
      "video"
      "wheel"
    ];
    openssh.authorizedKeys.keys = config.custom.authorizedKeys ++ [
      # hass-fnuc
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKtJvOe/V+obZ1lS2L/qUAUVDUSFapVKin07BUZSHAU7"
    ];
    shell = pkgs.zsh;
  };

  users.users.root.openssh.authorizedKeys.keys = config.custom.authorizedKeys;

  # Disable password prompts for wheel users when sudo'ing
  security.sudo.wheelNeedsPassword = false;

  # firmware updates
  services.fwupd.enable = true;

  # Enable flatpak
  services.flatpak = {
    enable = true;
    remotes = {
      "flathub" = "https://dl.flathub.org/repo/flathub.flatpakrepo";
      "flathub-beta" = "https://dl.flathub.org/beta-repo/flathub-beta.flatpakrepo";
    };
    packages = [ ];
  };

  # mlocate
  services.locate = {
    enable = true;
    package = pkgs.plocate;
    interval = "daily";
    localuser = null; # scan as root
  };

  # OpenSSH server
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = true;
    settings.KbdInteractiveAuthentication = true;
    settings.PermitRootLogin = "prohibit-password";
  };

  services.tailscale = {
    enable = true;
    openFirewall = true;
  };

  virtualisation = {
    podman = {
      enable = true;
      dockerCompat = false;
      defaultNetwork.settings = {
        dns_enabled = true;
      };
    };
    docker = {
      enable = true;
      storageDriver = "btrfs";
      package = pkgs.unstable.docker_24;
    };
  };

  programs.nix-ld = {
    enable = true;
    # libraries = [];
  };

  # Do not attempt to murder the laptop when running nixos rebuild
  nix = {
    daemonCPUSchedPolicy = "idle";
    daemonIOSchedClass = "idle";
  };
  # Do not use /tmp (50% RAM tmpfs) for builds
  systemd.services.nix-daemon.environment.TMPDIR = "/nix/tmp";
  # Create /nix/tmp and clean it up every 48 hours (2 days)
  systemd.tmpfiles.rules = [
    "d /nix/tmp 0755 root root 2d"
  ];

  programs.command-not-found.enable = false;

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

  programs.zsh = {
    enable = true;
    vteIntegration = true;
  };

  environment.shells = with pkgs; [ zsh ];
  # Make ZSH respect XDG
  environment.etc = {
    "zshenv.local" = {
      text = ''
        export ZDOTDIR="$HOME/.config/zsh"
      '';
      mode = "0644";
    };
  };

  hardware.enableAllFirmware = true;

  security.wrappers = {
    fping = {
      source = "${pkgs.fping}/bin/fping";
      setuid = true;
      owner = "root";
      group = "root";
    };
  };

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system = {
    stateVersion = "23.11";
    # autoUpgrade = {
    #   enable = true;
    #   channel = "https://nixos.org/channels/nixos-23.05";
    # };
  };

  # List services that you want to enable:
  services.avahi = {
    enable = true;
    nssmdns4 = true;
  };
}
