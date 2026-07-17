{ lib, ... }:
{
  imports = [
    ./hardware-configuration.nix

    ../../profiles/server
    ../../profiles/global/users/home-assistant.nix

    ../../services/nfs/nfs-client.nix

    ../../services/http.nix
    ../../services/tor.nix
  ];

  hardware = {
    cattle = false;
    serverType = "openstack";
    biosBoot = lib.mkForce false;
  };
  custom.promptColor = "#ff6600";

  services.nfsMounts.enable = true;

  # Enable networking
  networking = {
    hostName = lib.strings.trim (builtins.readFile ./HOSTNAME);
  };
}
