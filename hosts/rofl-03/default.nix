{ pkgs, config, ... }: {
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    ../../server
  ];

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
