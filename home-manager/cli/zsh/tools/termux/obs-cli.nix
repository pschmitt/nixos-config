{ inputs, pkgs, ... }:
{
  home.packages = [ inputs.obs-cli.packages.${pkgs.stdenv.hostPlatform.system}.obs-cli ];
}
