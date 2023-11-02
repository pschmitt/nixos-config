{ inputs, lib, config, pkgs, ... }:
{
  imports = [
    ./deckmaster.nix
    ./jcalapi.nix
    ./vpn.nix
  ];
}
