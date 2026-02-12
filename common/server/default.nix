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

    ../../hardware/openstack-wiit.nix
    ../../hardware/oci.nix

    ./dotfiles.nix
    ./firewall.nix
    ./monit.nix
    ./restic.nix
    ./snapper.nix
  ];

  hardware.type = lib.mkDefault "server";
  hardware.biosBoot = lib.mkDefault true;

  custom.syncthing.server = true;

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

  # Prefer Cloudflare DNS on servers (also used by some container modules that
  # read `config.networking.nameservers` to populate container resolv.conf).
  networking.nameservers = lib.mkDefault [
    "1.1.1.1"
    "1.0.0.1"
  ];

  # Make systemd-resolved use Cloudflare as its primary resolvers (not only as
  # fallback).
  services.resolved.settings.Resolve.DNS = [
    "1.1.1.1#one.one.one.one"
    "1.0.0.1#one.one.one.one"
  ];

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
