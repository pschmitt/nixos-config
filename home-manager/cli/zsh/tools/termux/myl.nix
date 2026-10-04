{ inputs, pkgs, ... }:
{
  home.packages = [ inputs.myl.packages.${pkgs.stdenv.hostPlatform.system}.myl ];
}
