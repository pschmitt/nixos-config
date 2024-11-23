# https://github.com/NixOS/nixpkgs/pull/119856/
{ lib, ... }:
{
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  custom.netbirdSetupKey = lib.mkForce "optimist";

  # HACK Fix netbird port forwarding
  # Set up NAT (Masquerading)
  networking.nat = {
    enable = true;
    externalInterface = "ens3";
    internalIPs = [ "100.122.0.0/16" ]; # Netbird subnet
  };
}
