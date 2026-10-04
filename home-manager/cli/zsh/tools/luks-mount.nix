{
  inputs,
  lib,
  pkgs,
  ...
}:
{
  home.packages = lib.optionals pkgs.stdenv.hostPlatform.isLinux [
    inputs.luks-mount.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
