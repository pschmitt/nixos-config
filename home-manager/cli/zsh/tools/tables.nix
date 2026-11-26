{ inputs, pkgs, ... }:
{
  # Table helpers the tsv::/gitlab:: functions pipe through.
  home.packages = [
    inputs.tsvtool.packages.${pkgs.stdenv.hostPlatform.system}.default
    pkgs.pycolumn
    pkgs.zebra
  ];
}
