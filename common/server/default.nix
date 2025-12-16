# See also: https://github.com/nix-community/srvos
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    ../global
    ../../services/mail

    ../global/users/github-actions.nix
    ../global/users/nix-remote-builder.nix
    ../../services/autoupgrade.nix
    ../../services/git-clone-nixos-config.nix
    ../../services/initrd-luks-ssh-unlock.nix

    ./dotfiles.nix
    ./firewall.nix
    ./monit.nix
    ./restic.nix
    ./snapper.nix
  ]
  ++ lib.optionals (config.hardware.serverType == "openstack") [ ../../hardware/openstack-wiit.nix ]
  ++ lib.optionals (config.hardware.serverType == "oci") [ ../../hardware/oci.nix ];

  hardware.type = lib.mkDefault "server";
  hardware.biosBoot = lib.mkDefault true;

  boot.kernel.sysctl = {
    # Raise inotify limits
    "fs.inotify.max_user_instances" = lib.mkForce 524288;
    "fs.inotify.max_user_watches" = lib.mkForce 524288;
  };

  # Write logs to console
  # https://github.com/nix-community/srvos/blob/main/nixos/common/serial.nix
  boot.kernelParams =
    if config.hardware.kvmGuest then
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
    dnsutils
    gitMinimal
    htop
    jq
    tmux
    inputs.tmux-slay.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
