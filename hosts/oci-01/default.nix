{ pkgs, ... }:
{
  imports = [
    ./disk-config.nix
    ./luks-data.nix
    ./hardware-configuration.nix

    ../../profiles/server

    ./http-static.nix
    ./healthchecks.nix
    ./stalwart.nix
    ./roundcube-native.nix
    ./mail-autoconfig.nix
    ./nginx-public.nix
    ./restic.nix
  ];

  hardware = {
    cattle = false;
    serverType = "oci";
  };

  networking.hostName = "oci-01";

  # nixos-install enters the target system while installing the boot loader
  # and needs util-linux's mount command there.
  environment.systemPackages = [ pkgs.util-linux ];
}
