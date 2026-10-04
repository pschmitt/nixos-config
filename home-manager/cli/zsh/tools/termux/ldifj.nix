{ inputs, pkgs, ... }:
{
  home.packages = [ inputs.ldifj.packages.${pkgs.stdenv.hostPlatform.system}.default ];
}
