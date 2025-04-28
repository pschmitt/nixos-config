{ lib, ... }:
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    ../../server
    ../../server/optimist.nix

    (import ../../services/nfs-client.nix { })
    ../../services/miner.nix
    ../../services/tdarr.nix
  ];

  custom.cattle = true;
  services.xmrig.settings.cpu.max-threads-hint = lib.mkForce 75;

  # Enable networking
  networking = {
    hostName = "rofl-05";
    # Disable the firewall altogether.
    firewall = {
      enable = false;
      # allowedTCPPorts = [ ... ];
      # allowedUDPPorts = [ ... ];
    };
  };
}
