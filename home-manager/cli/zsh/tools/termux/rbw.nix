{ inputs, pkgs, ... }:
{
  home.packages = [ inputs.rbw.packages.${pkgs.stdenv.hostPlatform.system}.rbw ];
}
