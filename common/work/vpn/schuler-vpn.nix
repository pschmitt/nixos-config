{ pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.openconnect
    pkgs.vpn-slice
  ];
}
