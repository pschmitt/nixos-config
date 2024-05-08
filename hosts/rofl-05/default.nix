{ ... }: {
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    ../../server

    ../../misc/nfs-client.nix
    ../../misc/miner.nix
    ../../misc/tdarr.nix
  ];

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
