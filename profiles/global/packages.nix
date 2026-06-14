{
  inputs,
  lib,
  pkgs,
  ...
}:
{
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
    systemctl-service-exec
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
}
