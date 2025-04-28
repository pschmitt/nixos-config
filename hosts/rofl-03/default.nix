{ ... }:
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    ../../server
    ../../server/optimist.nix

    (import ../../services/nfs-client.nix { })
    ../../services/tdarr.nix
    ../../services/miner.nix
    ../../services/http.nix
    ../../services/harmonia.nix
  ];

  custom.promptColor = "yellow";

  # Enable networking
  networking = {
    hostName = "rofl-03";
    # Disable the firewall altogether.
    firewall = {
      enable = false;
      # allowedTCPPorts = [ ... ];
      # allowedUDPPorts = [ ... ];
    };
  };
}
