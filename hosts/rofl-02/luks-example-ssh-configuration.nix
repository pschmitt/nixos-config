# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Setup keyfile
  boot.initrd.secrets = {
    "/crypto_keyfile.bin" = null;
  };

  # initrd ssh setup
  boot.initrd.enable = true;
  # networking.useDHCP = true;  # conflicts with networkmanager
  boot.kernelParams = [ "ip=dhcp" ];
  # Below is required to at least have one DNS server configured.
  # https://github.com/NixOS/nixpkgs/issues/63941
  services.resolved = {
    enable = true;
    fallbackDns = [ "1.1.1.1#one.one.one.one" "1.0.0.1#one.one.one.one" ];
    # If you enable DNSOverTLS here it will by default be used for *all* interfaces
    # -> If your connection does not support DoT then you need to explicitly disable it:
    # $ nmcli connection modify "Wired connection 1" connection.dns-over-tls 0
    # https://askubuntu.com/questions/1310096/per-link-dns-over-tls-setting-networkmanager-systemd-resolved
    # extraConfig = ''
    #   DNSOverTLS=yes
    # '';
  };
  boot.initrd.network = {
    enable = true;
    flushBeforeStage2 = true;
    ssh = {
      enable = true;
      port = 22;
      # authorizedKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEOsodZo47l6by834BZ52mEI14gIs7GRxpRRAnocWlA2 pschmitt@x13" ];
      authorizedKeys = config.users.users.pschmitt.openssh.authorizedKeys.keys;
      hostKeys = [ "/etc/secrets/initrd/ssh_host_rsa_key" "/etc/secrets/initrd/ssh_host_ed25519_key" ];
    };
  };

  # More experiments in hope of getting network to work in initrd
  # boot.initrd.systemd = {
  #   enable = true;
  #   emergencyAccess = true;
  #   network = {
  #     enable = true;
  #   };
  # };

  # below might be required for early network stack in bootloader, for luks unlocking via ssh
  # Alternative: import <nixpkgs/nixos/modules/profiles/qemu-guest.nix>
  # boot.initrd.availableKernelModules = [ "virtio_pci" ];

  networking.hostName = "nixos"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Set *global* nameservers
  # networking.nameservers = [ "1.1.1.1#one.one.one.one" "1.0.0.1#one.one.one.one" ];

  # Enable networking
  networking.networkmanager = {
    enable = true;
    dns = "systemd-resolved";
  };

  systemd.services.nmcli-wired = {
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      description = ''Force enable "Wired Connection"'';
      serviceConfig = {
        Type = "oneshot";
        ExecStart = ''${pkgs.networkmanager}/bin/nmcli con up "Wired connection 1"'';
      };
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

  # Configure keymap in X11
  services.xserver = {
    layout = "de";
    xkbVariant = "";
  };

  # Configure console keymap
  console.keyMap = "de";

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.pschmitt = {
    isNormalUser = true;
    description = "Philipp Schmitt";
    extraGroups = [ "networkmanager" "wheel" "docker" ];
    packages = with pkgs; [];
    # openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEOsodZo47l6by834BZ52mEI14gIs7GRxpRRAnocWlA2 pschmitt@x13" ];
    # https://discourse.nixos.org/t/fetching-ssh-public-keys/12076/7
    openssh.authorizedKeys.keys = let
      authorizedKeys = builtins.fetchurl "https://github.com/pschmitt.keys";
      in pkgs.lib.splitString "\n" (builtins.readFile authorizedKeys);
    shell = pkgs.zsh;
  };

  # Enable automatic login for the user.
  services.getty.autologinUser = "pschmitt";
  # Disable password prompts for wheel users when sudo'ing
  security.sudo.wheelNeedsPassword = false;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # ??
  environment.enableAllTerminfo = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    bind # dig
    curl
    jq
    yq-go
    neovim
    nmap
    pciutils  # lspci
    ripgrep
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
    tmux
    wget
  ];

  programs.zsh.enable = true;
  environment.shells = with pkgs; [ zsh ];

  programs.neovim = {
    enable = true;
    defaultEditor = true;
  };

  programs.hyprland.enable = true;

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  networking.firewall.enable = false;

  virtualisation.docker = {
    enable = true;
    # storageDriver = "btrfs";
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.05"; # Did you read the comment?

}

# vim: set ft=nix et ts=2 sw=2 :
