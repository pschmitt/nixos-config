{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ../network
    ./appimage.nix
    ./atd.nix
    ./bootloader.nix
    ./containers.nix
    ./dict.nix
    ./dotfiles.nix
    ./locales.nix
    ./nix.nix
    ./users.nix
    ./sops.nix
    ./ssh.nix
  ];

  boot = {
    kernel.sysctl = {
      # Enable all MagicSysRq keys
      "kernel.sysrq" = 1;
    };
    kernelPackages = lib.mkDefault (
      if config.custom.raspberryPi then
        pkgs.linuxKernel.packages.linux_rpi4
      else
        pkgs.linuxPackages_latest
    );
    tmp = {
      useTmpfs = true;
    };
  };

  hardware.enableAllFirmware = true;

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
    fd
    fx
    git
    grc
    htop
    hwatch
    jq
    killall
    lm_sensors
    luks-mount
    mediainfo
    moreutils # ts among others
    ncdu
    p7zip
    pciutils # lspci
    pinentry-curses
    procps # coreutils' uptime does not have the -s flag
    (lib.hiPrio parallel-full) # GNU Parallel, note that moreutils also ships parallel
    openssl
    psmisc # pstree, killall, fuser
    pwgen
    ripgrep
    socat
    sshpass
    tmux
    tmux-slay
    yank-osc52
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

    # python
    python3Packages.pip
    pipx
    uv
    # main python pkgs
    (python3.withPackages (
      ps: with ps; [
        dbus-python
        dnspython # for ansible
        gst-python
        pygobject3
        pynvim
        requests
        rich
      ]
    ))
  ];

  users.users.root.openssh.authorizedKeys.keys = config.custom.authorizedKeys;

  # Disable password prompts for wheel users when sudo'ing
  security.sudo.wheelNeedsPassword = false;

  # firmware updates
  services = {
    fwupd.enable = true;

    # mlocate
    locate = {
      enable = true;
      package = pkgs.plocate;
      interval = "daily";
    };

    # OpenSSH server
    openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = true;
        KbdInteractiveAuthentication = true;
        PermitRootLogin = "prohibit-password";
        # Let clients pick the bind address (e.g. 0.0.0.0)
        GatewayPorts = "clientspecified";
      };
      sftpServerExecutable = "internal-sftp";
      extraConfig = ''
        AcceptEnv TERM_SSH_CLIENT
      '';
    };
  };

  # started in user sessions.
  # programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    # pinentryPackage = pkgs.pinentry-gnome3;
    enableSSHSupport = true;
  };
}
