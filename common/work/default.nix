{ inputs, lib, config, pkgs, ... }:
{
  imports = [
    ./deckmaster.nix
    ./jcalapi.nix
    ./vpn/openvpn.nix
    ./vpn/openconnect.nix
  ];
}
