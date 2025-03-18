{ lib, ... }:
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    ../../server
    ../../server/optimist.nix

    ../../services/miner.nix
    ../../services/http.nix
    ../../services/monerod.nix
  ];

  custom.cattle = true;
  services.xmrig.settings.cpu.max-threads-hint = lib.mkForce 15;

  # Enable networking
  networking = {
    hostName = "rofl-06";
    # Disable the firewall altogether.
    firewall = {
      enable = false;
      # allowedTCPPorts = [ ... ];
      # allowedUDPPorts = [ ... ];
    };
  };
}
