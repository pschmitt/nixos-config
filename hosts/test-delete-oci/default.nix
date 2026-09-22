{ lib, ... }:
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    ./hardware.nix

    ../../profiles/specializations/server
  ];

  hardware.cattle = true;

  networking = {
    hostName = lib.strings.trim (builtins.readFile ./HOSTNAME);
    firewall.enable = false;
  };
}
