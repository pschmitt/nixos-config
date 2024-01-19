{ inputs, lib, config, pkgs, ... }:
{
  imports = [
    ./deckmaster.nix
    ./jcalapi.nix
    ./vpn/schuler-vpn.nix
    ./vpn/netbird.nix
    # ./vpn/openconnect.nix
    ./vpn/openvpn.nix
  ];
}
