{ ... }:
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    ../../server
    ../../server/optimist.nix

    ../../services/harmonia.nix
    ../../services/http.nix
    ../../services/miner.nix
    ../../services/nfs/nfs-client-rofl-07.nix
    ../../services/tdarr-node.nix
  ];

  custom.cattle = false;
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
