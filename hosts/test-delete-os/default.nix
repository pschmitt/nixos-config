{ lib, ... }:
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    ./luks-data.nix

    ../../profiles/specializations/server
  ];

  hardware.cattle = true;
  hardware.serverType = "openstack";

  # Enable networking
  networking = {
    hostName = lib.strings.trim (builtins.readFile ./HOSTNAME);
    # Disable the firewall altogether.
    firewall = {
      enable = false;
      # allowedTCPPorts = [ ... ];
      # allowedUDPPorts = [ ... ];
    };
  };

  # environment.systemPackages = with pkgs; [ ];

  # Pinned per host: bumping it changes stateful service defaults.
  # https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion
  system.stateVersion = "25.11";
}
