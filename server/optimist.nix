# https://github.com/NixOS/nixpkgs/pull/119856/
{ lib, ... }: {
  custom.netbirdSetupKey = lib.mkForce "optimist";
}
