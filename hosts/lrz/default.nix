{ pkgs, config, ... }: {
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    ../../server
  ];

  custom.useBIOS = false;

  # Enable networking
  networking = {
    hostName = "lrz";
    # Disable the firewall altogether.
    firewall = {
      enable = false;
      # allowedTCPPorts = [ ... ];
      # allowedUDPPorts = [ ... ];
    };
  };

}
