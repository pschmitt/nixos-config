{ lib, pkgs, ... }:
{
  networking.firewall = {
    enable = lib.mkDefault true;
    allowPing = lib.mkDefault true;
    checkReversePath = lib.mkDefault "loose";

    # DEBUG
    # logReversePathDrops = true;
    # logRefusedPackets = true;
    # logRefusedConnections = true;
  };

  environment.systemPackages = [
    pkgs.nftables
  ];
}
