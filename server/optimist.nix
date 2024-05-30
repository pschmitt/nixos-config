# https://github.com/NixOS/nixpkgs/pull/119856/
{ lib, ... }:
{
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  custom.netbirdSetupKey = lib.mkForce "optimist";
}
