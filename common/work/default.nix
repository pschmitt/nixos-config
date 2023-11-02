{ inputs, lib, config, pkgs, ... }:
{
  imports = [
    ./jcalapi.nix
    ./vpn.nix
  ];
}
