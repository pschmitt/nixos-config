{ lib, ... }:
{
  networking.firewall = {
    enable = lib.mkDefault true;
    allowedTCPPorts = lib.mkBefore [ 22 443 ];
    checkReversePath = lib.mkDefault "loose";
  };
}
