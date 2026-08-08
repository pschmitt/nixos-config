{ pkgs, ... }:
{
  imports = [
    ./disk-config.nix
    ./luks-data.nix
    ./hardware-configuration.nix

    ../../profiles/server

    ./http-static.nix
    ./legacy-services.nix
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
