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
    # internalIPs = [
    #   # Netbird subnet
    #   "100.122.0.0/16"
    #   # Tailscale
    #   "100.64.0.0/10"
    # ];
    internalInterfaces = [
      # netbird-netbird-io
      "netbird-io"
      # netbird-wiit
      "wiit"
      # default nb interface name
      # "netbird0"
      "wt0"

      # tailscale default interface name
      "tailscale0"
    ];
  };
}
