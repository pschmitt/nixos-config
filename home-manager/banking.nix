{ inputs, pkgs, ... }:
{
  home.packages = [
    inputs.bunq-sh.packages.${pkgs.stdenv.hostPlatform.system}.bunq
    pkgs.cdpcurl
    pkgs.pytr
  ];
}
