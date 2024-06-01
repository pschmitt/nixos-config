{ ... }:
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    ../../server
    ../../server/optimist.nix

    ../../misc/nfs-client.nix
    ../../misc/tdarr.nix
    ../../misc/miner.nix
    ../../misc/http.nix
    ../../misc/harmonia.nix
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
