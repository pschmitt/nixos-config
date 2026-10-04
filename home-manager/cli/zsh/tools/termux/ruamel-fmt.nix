{ inputs, pkgs, ... }:
{
  home.packages = [ inputs.ruamel-fmt.packages.${pkgs.stdenv.hostPlatform.system}.default ];
}
