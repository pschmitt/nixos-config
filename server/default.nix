# See also: https://github.com/nix-community/srvos
{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ../common/global
    ../common/mail

    ../misc/autoupgrade.nix
    ../misc/git-clone-nixos-config.nix
    ../misc/initrd-luks-ssh-unlock.nix
    ../misc/users/github-actions.nix
    ../misc/users/nix-remote-builder.nix

    ./dotfiles.nix
    ./monit.nix
    ./netbird.nix
    ./restic.nix
  ];

  custom.server = true;
  custom.useBIOS = lib.mkDefault true;

  boot.kernel.sysctl = {
    # Raise inotify limits
    "fs.inotify.max_user_instances" = lib.mkDefault 524288;
    "fs.inotify.max_user_watches" = lib.mkDefault 524288;
  };

  # Write logs to console
  # https://github.com/nix-community/srvos/blob/main/nixos/common/serial.nix
  boot.kernelParams =
    if config.custom.kvmGuest then
      [
        "console=tty0"
        "console=ttyS0,115200"
      ]
    else
      [ ];

  # boot.kernel.sysctl = {
  #   "net.core.default_qdisc" = "fq";
  #   "net.ipv4.tcp_congestion_control" = "bbr";
  # };

  networking.useNetworkd = lib.mkDefault true;

  programs.nix-index-database.comma.enable = true;

  environment.systemPackages = with pkgs; [
    curl
    docker-compose-bulk
    dnsutils
    gitMinimal
    htop
    jq
    tmux
    tmux-slay
  ];
}
