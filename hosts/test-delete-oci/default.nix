{ lib, ... }:
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    ./hardware.nix
    ./luks-data.nix

    ../../profiles/specializations/server
  ];

  hardware.cattle = true;

  networking = {
    hostName = lib.strings.trim (builtins.readFile ./HOSTNAME);
    firewall.enable = false;
  };

  # Pinned per host: bumping it changes stateful service defaults.
  # https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion
  system.stateVersion = "25.11";
}
