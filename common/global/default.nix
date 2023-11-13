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

  authorizedKeysContent = builtins.readFile (builtins.fetchurl {
    url = "https://github.com/pschmitt.keys";
    sha256 = "0z65rk873yc2bl6fk5y2czin260s5f5cqnzcw51bxyvshdwvp0kg";
  });

  authorizedKeys = pkgs.lib.filter (key: key != "") (pkgs.lib.splitString "\n" authorizedKeysContent);

in
{
  imports = [ ./printer.nix ];

  nixpkgs = {
    # You can add overlays here
    overlays = [
      # Add overlays your own flake exports (from overlays and pkgs dir):
      outputs.overlays.additions
      outputs.overlays.modifications
      outputs.overlays.unstable-packages

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
    jq
    killall
    lm_sensors
    mediainfo
    moreutils # ts among others
    nethogs
    ookla-speedtest
    nmap
    pciutils # lspci
    usbutils # lsusb
    pinentry-curses
    procps # coreutils' uptime does not have the -s flag
    pstree
    pwgen
    ripgrep
    socat
    sshpass
    tailscale
    tmux
    tree
    unzip
    p7zip
    zip
    wget
    yq-go

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
      "input" # for ydotool
      "libvirtd"
      "mlocate"
      "networkmanager"
      "pschmitt"
      "video"
      "wheel"
    ];
    packages = with pkgs; [ ];
    openssh.authorizedKeys.keys = authorizedKeys;
    shell = pkgs.zsh;
  };

  users.users.root.openssh.authorizedKeys.keys = authorizedKeys;

  # Disable password prompts for wheel users when sudo'ing
  security.sudo.wheelNeedsPassword = false;

  # firmware updates
  services.fwupd.enable = true;

  # Enable flatpak
  services.flatpak.enable = true;

  # flathub
  # https://discourse.nixos.org/t/confusion-about-proper-way-to-setup-flathub/29806/12
  system.userActivationScripts = {
    flathub = {
      text = ''
        ${pkgs.flatpak}/bin/flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
      '';
    };
  };

  # mlocate
  services.locate = {
    enable = true;
    package = pkgs.plocate;
    interval = "daily";
    localuser = null; # scan as root
  };

  # This setups a SSH server. Very important if you're setting up a headless system.
  # Feel free to remove if you don't need it.
  services.openssh = {
    enable = true;
    # Forbid root login through SSH.
    # permitRootLogin = "no";
    # Use keys only. Remove if you want to SSH using password (not recommended)
    # passwordAuthentication = false;
  };

  services.tailscale = { enable = true; };

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

  programs.zsh.enable = true;
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
    stateVersion = "23.05";
    # autoUpgrade = {
    #   enable = true;
    #   channel = "https://nixos.org/channels/nixos-23.05";
    # };
  };
}
