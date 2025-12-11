{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    ../network
    ./appimage.nix
    ./atd.nix
    ./btrfs.nix
    ./bootloader.nix
    ./containers.nix
    ./dict.nix
    ./dotfiles.nix
    ./locales.nix
    ./nix.nix
    ./sops.nix
    ./ssh.nix
    ./users.nix
  ];

  boot = {
    kernel.sysctl = {
      # Enable all MagicSysRq keys
      "kernel.sysrq" = 1;
    };
    kernelPackages = lib.mkDefault (
      if config.hardware.type == "rpi" then
        pkgs.linuxKernel.packages.linux_rpi4
      else
        pkgs.linuxPackages_latest
    );
    tmp = {
      useTmpfs = true;
    };
  };

  hardware.enableAllFirmware = true;

  environment.sessionVariables.HOSTNAME = config.networking.hostName;
  environment.systemPackages = with pkgs; [
    # misc
    acpi
    b3sum
    bc
    git
    grc
    htop
    hwatch
    pinentry-curses
    pwgen
    systemd-service-exec
    tmux
    inputs.tmux-slay.packages.${pkgs.stdenv.hostPlatform.system}.default
    yank-osc52

    # sensors and devices
    lm_sensors
    pciutils # lspci
    usbutils # lsusb

    # coreutils
    moreutils # ts among others
    killall
    psmisc # pstree, killall, fuser
    procps # coreutils' uptime does not have the -s flag
    (lib.hiPrio parallel-full) # GNU Parallel, note that moreutils also ships parallel

    # files
    dua # ncdu on steroids
    fd
    file
    mediainfo
    ncdu
    p7zip
    unzip
    zip

    # the greps
    ripgrep
    tree
    ugrep

    # json/yaml/xml
    fx
    jq
    yq-go

    # fs
    cryptsetup
    exfatprogs
    inputs.luks-mount.packages.${pkgs.stdenv.hostPlatform.system}.default
    xfsprogs

    # python
    pipx
    uv
  ];

  # Disable password prompts for wheel users when sudo'ing
  security.sudo.wheelNeedsPassword = false;

  services = {
    # firmware updates
    fwupd.enable = true;

    # mlocate
    locate = {
      enable = true;
      package = pkgs.plocate;
      interval = "daily";
    };
  };
}
