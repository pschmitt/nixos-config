{ ... }:
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    ../../server
    ../../server/optimist.nix

    ../../services/harmonia.nix
    ../../services/http.nix
    ../../services/nfs/nfs-client-rofl-11.nix
    ../../services/tdarr-node.nix
    ../../services/xmr/xmrig.nix
  ];

  custom.cattle = true;
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
