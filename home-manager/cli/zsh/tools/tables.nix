{ inputs, pkgs, ... }:
{
  # Table helpers the tsv::/gitlab:: functions pipe through. zinit hosts get
  # the uv-script versions from yadm's ~/bin instead.
  home.packages = [
    inputs.tsvtool.packages.${pkgs.stdenv.hostPlatform.system}.default
    pkgs.pycolumn
    pkgs.zebra
  ];
}
