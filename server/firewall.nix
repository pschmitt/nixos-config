{ lib, ... }:
{
  networking.firewall = {
    enable = lib.mkDefault true;
    allowPing = lib.mkDefault true;
    allowedTCPPorts = lib.mkBefore [
      22
      80
      443
    ];
    checkReversePath = lib.mkDefault "loose";

    # DEBUG
    # logReversePathDrops = true;
    # logRefusedPackets = true;
    logRefusedConnections = true;
  };
}
