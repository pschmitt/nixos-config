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
    ../../services/xmrig-proxy.nix
  ];

  custom.cattle = true;
  custom.promptColor = "#ff6600";

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
