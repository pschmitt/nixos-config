{ lib, ... }:
{
  imports = [
    ./hardware-configuration.nix

    ../../profiles/server
    ../../profiles/tdarr-node.nix
  ];

  hardware = {
    cattle = true;
    serverType = "openstack";
  };
  custom.promptColor = "magenta";

  # Enable networking
  networking = {
    hostName = lib.strings.trim (builtins.readFile ./HOSTNAME);
  };

  # environment.systemPackages = with pkgs; [ ];
}
