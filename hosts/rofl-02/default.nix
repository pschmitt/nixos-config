{ pkgs, ... }: {
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    ../../server

    ./luks-data.nix
  ];

  # Enable networking
  networking = {
    hostName = "rofl-02";
    # Disable the firewall altogether.
    firewall = {
      enable = false;
      # allowedTCPPorts = [ ... ];
      # allowedUDPPorts = [ ... ];
    };
  };

  services.harmonia = {
    enable = true;
    settings = {
      bind = "100.85.145.107:5000";
    };
  };
}
