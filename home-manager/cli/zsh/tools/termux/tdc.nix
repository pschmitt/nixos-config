{ inputs, pkgs, ... }:
{
  home.packages = [ inputs.tdc.packages.${pkgs.stdenv.hostPlatform.system}.tdc ];
}
