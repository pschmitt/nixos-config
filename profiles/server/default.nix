# See also: https://github.com/nix-community/srvos
{
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

    ./ansible.nix
    ./boot.nix
    ./dotfiles.nix
    ./firewall.nix
    ./monit.nix
    ./networking.nix
    ./restic.nix
    ./snapper.nix
  ];

  hardware.type = lib.mkDefault "server";
  hardware.biosBoot = lib.mkDefault true;

  custom.syncthing.server = true;

  services.dbus.implementation = "broker";

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
