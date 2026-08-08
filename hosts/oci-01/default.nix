{ pkgs, ... }:
{
  imports = [
    ./disk-config.nix
    ./luks-data.nix
    ./hardware-configuration.nix

    ../../profiles/server
    ../../profiles/email-server.nix

    ./http-static.nix
    ../../services/healthchecks.nix
    ./nginx-public.nix
    ./restic.nix
  ];

  hardware = {
    cattle = false;
    serverType = "oci";
  };

  networking.hostName = "oci-01";

  # Keep the existing client autoconfiguration endpoint for schmitt.co.
  services.mail-autoconfig.domain = "schmitt.co";

  # nixos-install enters the target system while installing the boot loader
  # and needs util-linux's mount command there.
  environment.systemPackages = [ pkgs.util-linux ];
}
