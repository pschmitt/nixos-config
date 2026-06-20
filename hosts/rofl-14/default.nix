{ lib, ... }:
{
  imports = [
    ./hardware-configuration.nix

    ../../profiles/server
    ../../profiles/tdarr-node.nix
    ../../services/esphome.nix
  ];

  hardware = {
    cattle = true;
    serverType = "openstack";
  };
  custom.promptColor = "magenta";
  nixHost.extraSubstituters = [
    "https://cache.rofl-10.brkn.lol"
    "https://cache.rofl-13.brkn.lol"
  ];

  # Enable networking
  networking = {
    hostName = lib.strings.trim (builtins.readFile ./HOSTNAME);
  };

  # environment.systemPackages = with pkgs; [ ];
}
