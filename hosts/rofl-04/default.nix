{ ... }: {
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    ../../server
    ../../misc/nfs-client.nix

    ./tdarr.nix
  ];

  # Enable networking
  networking = {
    hostName = "rofl-04";
    # Disable the firewall altogether.
    firewall = {
      enable = false;
      # allowedTCPPorts = [ ... ];
      # allowedUDPPorts = [ ... ];
    };
  };

}
