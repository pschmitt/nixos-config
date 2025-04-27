{ ... }:
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    ./luks-data.nix

    ../../server
    ../../server/optimist.nix

    (import ../../services/nfs-client.nix { mountPoint = "/mnt/rofl-02"; })
  ];

  custom.cattle = true;

  # Enable networking
  networking = {
    hostName = "rofl-07";
    # Disable the firewall altogether.
    firewall = {
      enable = false;
      # allowedTCPPorts = [ ... ];
      # allowedUDPPorts = [ ... ];
    };
  };
}
