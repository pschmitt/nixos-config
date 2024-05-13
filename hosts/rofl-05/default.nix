{ lib, ... }: {
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    ../../server

    ../../misc/nfs-client.nix
    ../../misc/miner.nix
    ../../misc/tdarr.nix
  ];

  custom.cattle = true;
  services.xmrig.settings.cpu.max-threads-hint = 75;

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
