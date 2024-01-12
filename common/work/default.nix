{ inputs, lib, config, pkgs, ... }:
{
  imports = [
    ./deckmaster.nix
    ./jcalapi.nix
    ./vpn/schuler-vpn.nix
    ./vpn/openvpn.nix
    ./vpn/openconnect.nix
  ];
}
