{ config, pkgs, ... }:
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
    ../network
    ./appimage.nix
    ./atd.nix
    ./bootloader.nix
    ./dotfiles.nix
    ./nix.nix
    ./pschmitt.nix
    ./sops.nix
    ./ssh.nix
  ];

  boot = {
    # Enable all MagicSysRq keys
    kernel.sysctl = { "kernel.sysrq" = 1; };
    kernelPackages = pkgs.linuxPackages_latest;
    tmp = { useTmpfs = true; };
  };

  hardware.enableAllFirmware = true;

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

  environment.systemPackages = with pkgs; [
    # core
    acpi
    autossh
    bc
    bind # dig
    cryptsetup
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
    luks-mount
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
    tmux-slay
    tree
    ugrep
    unzip
    usbutils # lsusb
    wget
    yq-go
    zip

    # mkfs
    exfatprogs
    xfsprogs

    # devel
    cargo
    gcc
    gnumake
    go
    nodejs
    podman-compose
    pkg-config
    # (python3.withPackages(python-packages))
    # (python310.withPackages(python-packages))
    (python311.withPackages (python-packages))
    unstable.rustc
    openssl
  ];

  users.users.root.openssh.authorizedKeys.keys = config.custom.authorizedKeys;

  # Disable password prompts for wheel users when sudo'ing
  security.sudo.wheelNeedsPassword = false;

  # firmware updates
  services.fwupd.enable = true;

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
    };
  };

  # started in user sessions.
  # programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    # pinentryPackage = pkgs.pinentry-gnome3;
    enableSSHSupport = true;
  };

  security.wrappers = {
    fping = {
      source = "${pkgs.fping}/bin/fping";
      setuid = true;
      owner = "root";
      group = "root";
    };
  };

  # create a wireshark wrapper
  programs.wireshark.enable = true;
}
