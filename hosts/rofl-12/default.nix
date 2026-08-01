{ config, lib, ... }:
{
  imports = [
    ./hardware-configuration.nix

    ../../profiles/server
    ../../profiles/network/roflnet.nix
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

  services.nfsMounts = {
    enable = true;
    server = "rofl-10.${config.domains.roflnet}";
  };

  # Enable networking
  networking = {
    hostName = lib.strings.trim (builtins.readFile ./HOSTNAME);
  };
}
